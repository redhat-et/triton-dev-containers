#!/usr/bin/env python
"""
Flash attention kernel for Triton.
Based on https://github.com/vllm-project/vllm/blob/main/vllm/attention/ops/triton_flash_attention.py
"""

import torch
import triton
import triton.language as tl

# ------------------------------------------------------------
# Backend Detection Helpers
# ------------------------------------------------------------
def is_cuda():
    return triton.runtime.driver.active.get_current_target().backend == "cuda"

# ------------------------------------------------------------
# Helper Functions for Flash Attention
# ------------------------------------------------------------
@triton.jit
def cdiv_fn(x, y):
    return (x + y - 1) // y

@triton.jit
def max_fn(x, y):
    return tl.math.max(x, y)

@triton.jit
def dropout_offsets(philox_seed, philox_offset, dropout_p, m, n, stride):
    ms = tl.arange(0, m)
    ns = tl.arange(0, n)
    return philox_offset + ms[:, None] * stride + ns[None, :]

@triton.jit
def dropout_rng(philox_seed, philox_offset, dropout_p, m, n, stride):
    rng_offsets = dropout_offsets(philox_seed, philox_offset, dropout_p, m, n, stride).to(tl.uint32)
    return tl.rand(philox_seed, rng_offsets)

@triton.jit
def dropout_mask(philox_seed, philox_offset, dropout_p, m, n, stride):
    rng_output = dropout_rng(philox_seed, philox_offset, dropout_p, m, n, stride)
    rng_keep = rng_output > dropout_p
    return rng_keep

@triton.jit
def load_fn(block_ptr, first, second, pad):
    if first and second:
        tensor = tl.load(block_ptr, boundary_check=(0, 1), padding_option=pad)
    elif first:
        tensor = tl.load(block_ptr, boundary_check=(0, ), padding_option=pad)
    elif second:
        tensor = tl.load(block_ptr, boundary_check=(1, ), padding_option=pad)
    else:
        tensor = tl.load(block_ptr)
    return tensor

@triton.jit
def _attn_fwd_inner(
    acc,
    l_i,
    m_i,
    q,
    K_block_ptr,
    V_block_ptr,
    start_m,
    actual_seqlen_k,
    dropout_p,
    philox_seed,
    batch_philox_offset,
    encoded_softmax_block_ptr,
    block_min,
    block_max,
    offs_n_causal,
    masked_blocks,
    n_extra_tokens,
    bias_ptr,
    IS_CAUSAL: tl.constexpr,
    BLOCK_M: tl.constexpr,
    BLOCK_DMODEL: tl.constexpr,
    BLOCK_N: tl.constexpr,
    OFFS_M: tl.constexpr,
    OFFS_N: tl.constexpr,
    PRE_LOAD_V: tl.constexpr,
    MASK_STEPS: tl.constexpr,
    ENABLE_DROPOUT: tl.constexpr,
    RETURN_ENCODED_SOFTMAX: tl.constexpr,
    PADDED_HEAD: tl.constexpr,
):
    # Loop over key blocks and update the accumulator.
    for start_n in range(block_min, block_max, BLOCK_N):
        k = load_fn(
            K_block_ptr,
            PADDED_HEAD,
            MASK_STEPS and (n_extra_tokens != 0),
            "zero",
        )
        if PRE_LOAD_V:
            v = load_fn(
                V_block_ptr,
                MASK_STEPS and (n_extra_tokens != 0),
                PADDED_HEAD,
                "zero",
            )
        qk = tl.zeros([BLOCK_M, BLOCK_N], dtype=tl.float32)
        if MASK_STEPS:
            if (start_n + BLOCK_N == block_max) and (n_extra_tokens != 0):
                boundary_m = tl.full([BLOCK_M], actual_seqlen_k, dtype=tl.int32)
                size_n = start_n + OFFS_N[None, :]
                mask = size_n < boundary_m[:, None]
                qk = tl.where(mask, qk, float("-inf"))
        if IS_CAUSAL:
            causal_boundary = start_n + offs_n_causal
            causal_mask = OFFS_M[:, None] >= causal_boundary[None, :]
            qk = tl.where(causal_mask, qk, float("-inf"))
        qk += tl.dot(q, k)
        if bias_ptr is not None:
            bias = load_fn(bias_ptr, False, MASK_STEPS and (n_extra_tokens != 0), "zero")
            qk += bias * 1.44269504089
        m_ij = tl.maximum(m_i, tl.max(qk, 1))
        qk = qk - m_ij[:, None]
        p = tl.math.exp2(qk)
        l_ij = tl.sum(p, 1)
        if ENABLE_DROPOUT:
            philox_offset = (batch_philox_offset +
                             start_m * BLOCK_M * actual_seqlen_k + start_n - BLOCK_N)
            keep = dropout_mask(philox_seed, philox_offset, dropout_p, BLOCK_M, BLOCK_N, actual_seqlen_k)
            if RETURN_ENCODED_SOFTMAX:
                tl.store(encoded_softmax_block_ptr,
                         tl.where(keep, p, -p).to(encoded_softmax_block_ptr.type.element_ty))
            p = tl.where(keep, p, 0.0)
        elif RETURN_ENCODED_SOFTMAX:
            tl.store(encoded_softmax_block_ptr, p.to(encoded_softmax_block_ptr.type.element_ty))
        alpha = tl.math.exp2(m_i - m_ij)
        acc = acc * alpha[:, None]
        if not PRE_LOAD_V:
            v = load_fn(V_block_ptr, MASK_STEPS and (n_extra_tokens != 0), PADDED_HEAD, "zero")
        l_i = l_i * alpha + l_ij
        m_i = m_ij
        acc += tl.dot(p.to(V_block_ptr.type.element_ty), v)
        V_block_ptr = tl.advance(V_block_ptr, (BLOCK_N, 0))
        K_block_ptr = tl.advance(K_block_ptr, (0, BLOCK_N))
        if bias_ptr is not None:
            bias_ptr = tl.advance(bias_ptr, (0, BLOCK_N))
        if RETURN_ENCODED_SOFTMAX:
            encoded_softmax_block_ptr = tl.advance(encoded_softmax_block_ptr, (0, BLOCK_N))
    return acc, l_i, m_i

# ------------------------------------------------------------
# Flash Attention Autotune Configuration Helpers
# ------------------------------------------------------------
def get_cuda_flash_attention_config():
    return [
        triton.Config({"BLOCK_M": 256, "BLOCK_N": 64, "PRE_LOAD_V": False}, num_stages=1, num_warps=8),
        triton.Config({"BLOCK_M": 128, "BLOCK_N": 128, "PRE_LOAD_V": False}, num_stages=1, num_warps=4),
        triton.Config({"BLOCK_M": 256, "BLOCK_N": 128, "PRE_LOAD_V": False}, num_stages=1, num_warps=8),
        triton.Config({"BLOCK_M": 128, "BLOCK_N": 64,  "PRE_LOAD_V": False}, num_stages=1, num_warps=4),
        triton.Config({"BLOCK_M": 128, "BLOCK_N": 64,  "PRE_LOAD_V": True},  num_stages=1, num_warps=4),
        triton.Config({"BLOCK_M": 128, "BLOCK_N": 64,  "PRE_LOAD_V": False}, num_stages=1, num_warps=4),
        triton.Config({"BLOCK_M": 64,  "BLOCK_N": 64,  "PRE_LOAD_V": False}, num_stages=1, num_warps=8),
        triton.Config({"BLOCK_M": 32,  "BLOCK_N": 32,  "PRE_LOAD_V": False}, num_stages=1, num_warps=8),
        triton.Config({"BLOCK_M": 16,  "BLOCK_N": 16,  "PRE_LOAD_V": False}, num_stages=1, num_warps=4),
    ]

def get_hip_flash_attention_config():
    return [
        triton.Config({"BLOCK_M": 128, "BLOCK_N": 64, "waves_per_eu": 2, "PRE_LOAD_V": False}, num_stages=1, num_warps=4),
        triton.Config({"BLOCK_M": 64,  "BLOCK_N": 64, "waves_per_eu": 2, "PRE_LOAD_V": False}, num_stages=1, num_warps=4),
        triton.Config({"BLOCK_M": 64,  "BLOCK_N": 32, "waves_per_eu": 2, "PRE_LOAD_V": False}, num_stages=1, num_warps=4),
    ]

def get_flash_attention_autotune_config():
    if is_cuda():
        return get_cuda_flash_attention_config()
    else:
        return get_hip_flash_attention_config()

# ------------------------------------------------------------
# Flash Attention Forward Kernel
# ------------------------------------------------------------
@triton.autotune(
    configs=get_flash_attention_autotune_config(),
    key=['IS_CAUSAL', 'dropout_p', 'BLOCK_DMODEL'],
)
@triton.jit
def attn_fwd(
    Q,
    K,
    V,
    bias,
    sm_scale,
    L,
    Out,
    stride_qz,
    stride_qh,
    stride_qm,
    stride_qk,
    stride_kz,
    stride_kh,
    stride_kn,
    stride_kk,
    stride_vz,
    stride_vh,
    stride_vk,
    stride_vn,
    stride_oz,
    stride_oh,
    stride_om,
    stride_on,
    stride_bz,
    stride_bh,
    stride_bm,
    stride_bn,
    cu_seqlens_q,
    cu_seqlens_k,
    dropout_p,
    philox_seed,
    philox_offset_base,
    encoded_softmax,
    HQ: tl.constexpr,
    HK: tl.constexpr,
    ACTUAL_BLOCK_DMODEL: tl.constexpr,
    MAX_SEQLENS_Q: tl.constexpr,
    MAX_SEQLENS_K: tl.constexpr,
    VARLEN: tl.constexpr,
    IS_CAUSAL: tl.constexpr,
    BLOCK_M: tl.constexpr,
    BLOCK_DMODEL: tl.constexpr,
    BLOCK_N: tl.constexpr,
    PRE_LOAD_V: tl.constexpr,
    BIAS_TYPE: tl.constexpr,
    ENABLE_DROPOUT: tl.constexpr,
    RETURN_ENCODED_SOFTMAX: tl.constexpr,
):
    start_m = tl.program_id(0)
    off_h_q = tl.program_id(1)
    off_z = tl.program_id(2)
    offs_m = start_m * BLOCK_M + tl.arange(0, BLOCK_M)
    offs_n = tl.arange(0, BLOCK_N)
    if VARLEN:
        cu_seqlens_q_start = tl.load(cu_seqlens_q + off_z)
        cu_seqlens_q_end = tl.load(cu_seqlens_q + off_z + 1)
        seqlen_q = cu_seqlens_q_end - cu_seqlens_q_start
        if start_m * BLOCK_M > seqlen_q:
            return
        cu_seqlens_k_start = tl.load(cu_seqlens_k + off_z)
        cu_seqlens_k_end = tl.load(cu_seqlens_k + off_z + 1)
        seqlen_k = cu_seqlens_k_end - cu_seqlens_k_start
    else:
        cu_seqlens_q_start = 0
        cu_seqlens_k_start = 0
        seqlen_q = MAX_SEQLENS_Q
        seqlen_k = MAX_SEQLENS_K

    n_blocks = cdiv_fn(seqlen_k, BLOCK_N)
    if IS_CAUSAL:
        n_blocks_seqlen = cdiv_fn((start_m + 1) * BLOCK_M + seqlen_k - seqlen_q, BLOCK_N)
        n_blocks = min(n_blocks, n_blocks_seqlen)
        if n_blocks <= 0:
            o_offset = (off_z * stride_oz + cu_seqlens_q_start * stride_om + off_h_q * stride_oh)
            O_block_ptr = tl.make_block_ptr(
                base=Out + o_offset,
                shape=(seqlen_q, BLOCK_DMODEL),
                strides=(stride_om, stride_on),
                offsets=(start_m * BLOCK_M, 0),
                block_shape=(BLOCK_M, BLOCK_DMODEL),
                order=(1, 0),
            )
            acc = tl.zeros([BLOCK_M, BLOCK_DMODEL], dtype=Out.type.element_ty)
            tl.store(O_block_ptr, acc, boundary_check=(0, 1))
            return

    GROUP_SIZE: tl.constexpr = HQ // HK
    off_h_k = off_h_q // GROUP_SIZE if GROUP_SIZE != 1 else off_h_q

    n_extra_tokens = 0
    if seqlen_k < BLOCK_N:
        n_extra_tokens = BLOCK_N - seqlen_k
    elif seqlen_k % BLOCK_N:
        n_extra_tokens = seqlen_k % BLOCK_N
    padded_head = ACTUAL_BLOCK_DMODEL != BLOCK_DMODEL

    q_offset = (off_z * stride_qz + off_h_q * stride_qh + cu_seqlens_q_start * stride_qm)
    Q_block_ptr = tl.make_block_ptr(
        base=Q + q_offset,
        shape=(seqlen_q, ACTUAL_BLOCK_DMODEL),
        strides=(stride_qm, stride_qk),
        offsets=(start_m * BLOCK_M, 0),
        block_shape=(BLOCK_M, BLOCK_DMODEL),
        order=(1, 0),
    )
    k_offset = (off_z * stride_kz + off_h_k * stride_kh + cu_seqlens_k_start * stride_kn)
    K_block_ptr = tl.make_block_ptr(
        base=K + k_offset,
        shape=(ACTUAL_BLOCK_DMODEL, seqlen_k),
        strides=(stride_kk, stride_kn),
        offsets=(0, 0),
        block_shape=(BLOCK_DMODEL, BLOCK_N),
        order=(0, 1),
    )
    v_offset = (off_z * stride_vz + off_h_k * stride_vh + cu_seqlens_k_start * stride_vk)
    V_block_ptr = tl.make_block_ptr(
        base=V + v_offset,
        shape=(seqlen_k, ACTUAL_BLOCK_DMODEL),
        strides=(stride_vk, stride_vn),
        offsets=(0, 0),
        block_shape=(BLOCK_N, BLOCK_DMODEL),
        order=(1, 0),
    )
    if BIAS_TYPE != 0:
        bias_ptr = tl.make_block_ptr(
            base=bias + off_h_q * stride_bh,
            shape=(seqlen_q, seqlen_k),
            strides=(stride_bm, stride_bn),
            offsets=(start_m * BLOCK_M, 0),
            block_shape=(BLOCK_M, BLOCK_N),
            order=(1, 0),
        )
    else:
        bias_ptr = None
    if ENABLE_DROPOUT:
        batch_philox_offset = philox_offset_base + (off_z * HQ + off_h_q) * seqlen_q * seqlen_k
    else:
        batch_philox_offset = 0
    if RETURN_ENCODED_SOFTMAX:
        encoded_softmax_block_ptr = tl.make_block_ptr(
            base=encoded_softmax + off_h_q * seqlen_q * seqlen_k,
            shape=(seqlen_q, seqlen_k),
            strides=(seqlen_k, 1),
            offsets=(start_m * BLOCK_M, 0),
            block_shape=(BLOCK_M, BLOCK_N),
            order=(1, 0),
        )
    else:
        encoded_softmax_block_ptr = 0
    m_i = tl.full([BLOCK_M], float("-inf"), dtype=tl.float32)
    l_i = tl.full([BLOCK_M], 1.0, dtype=tl.float32)
    acc = tl.zeros([BLOCK_M, BLOCK_DMODEL], dtype=tl.float32)
    qk_scale = sm_scale * 1.44269504089
    q = load_fn(Q_block_ptr, True, padded_head, "zero")
    q = (q * qk_scale).to(Q_block_ptr.type.element_ty)

    padded_block_k = n_extra_tokens != 0
    is_modulo_mn = not padded_block_k and (seqlen_q % BLOCK_M == 0)
    if IS_CAUSAL:
        masked_blocks = BLOCK_M // BLOCK_N + (not is_modulo_mn)
    else:
        masked_blocks = padded_block_k
    masked_blocks = min(masked_blocks, n_blocks)
    n_full_blocks = n_blocks - masked_blocks
    block_min = 0
    block_max = n_blocks * BLOCK_N
    if n_full_blocks > 0:
        block_max = (n_blocks - masked_blocks) * BLOCK_N
        acc, l_i, m_i = _attn_fwd_inner(
            acc, l_i, m_i, q, K_block_ptr, V_block_ptr, start_m, seqlen_k,
            dropout_p, philox_seed, batch_philox_offset, encoded_softmax_block_ptr,
            block_min, block_max, 0, 0, 0, bias_ptr,
            False, BLOCK_M, BLOCK_DMODEL, BLOCK_N, offs_m, offs_n,
            PRE_LOAD_V, False, ENABLE_DROPOUT, RETURN_ENCODED_SOFTMAX, padded_head,
        )
        block_min = block_max
        block_max = n_blocks * BLOCK_N

    tl.debug_barrier()
    if masked_blocks > 0:
        offs_n_causal = offs_n + (seqlen_q - seqlen_k) if IS_CAUSAL else 0
        K_block_ptr = tl.advance(K_block_ptr, (0, n_full_blocks * BLOCK_N))
        V_block_ptr = tl.advance(V_block_ptr, (n_full_blocks * BLOCK_N, 0))
        if bias_ptr is not None:
            bias_ptr = tl.advance(bias_ptr, (0, n_full_blocks * BLOCK_N))
        if RETURN_ENCODED_SOFTMAX:
            encoded_softmax_block_ptr = tl.advance(encoded_softmax_block_ptr, (0, n_full_blocks))
        acc, l_i, m_i = _attn_fwd_inner(
            acc, l_i, m_i, q, K_block_ptr, V_block_ptr, start_m, seqlen_k,
            dropout_p, philox_seed, batch_philox_offset, encoded_softmax_block_ptr,
            block_min, block_max, offs_n_causal, masked_blocks, n_extra_tokens,
            bias_ptr, IS_CAUSAL, BLOCK_M, BLOCK_DMODEL, BLOCK_N, offs_m, offs_n,
            PRE_LOAD_V, True, ENABLE_DROPOUT, RETURN_ENCODED_SOFTMAX, padded_head,
        )
    acc = acc / l_i[:, None]
    if ENABLE_DROPOUT:
        acc = acc / (1 - dropout_p)
    end_m_idx = (start_m + 1) * BLOCK_M
    start_m_idx = start_m * BLOCK_M
    causal_start_idx = seqlen_q - seqlen_k
    acc = acc.to(Out.type.element_ty)
    if IS_CAUSAL:
        if causal_start_idx > start_m_idx and causal_start_idx < end_m_idx:
            out_mask_boundary = tl.full((BLOCK_DMODEL, ), causal_start_idx, dtype=tl.int32)
            mask_m_offsets = start_m_idx + tl.arange(0, BLOCK_M)
            out_ptrs_mask = (mask_m_offsets[:, None] >= out_mask_boundary[None, :])
            z = 0.0
            acc = tl.where(out_ptrs_mask, acc, z.to(acc.type.element_ty))
    o_offset = (off_z * stride_oz + cu_seqlens_q_start * stride_om + off_h_q * stride_oh)
    O_block_ptr = tl.make_block_ptr(
        base=Out + o_offset,
        shape=(seqlen_q, ACTUAL_BLOCK_DMODEL),
        strides=(stride_om, stride_on),
        offsets=(start_m * BLOCK_M, 0),
        block_shape=(BLOCK_M, BLOCK_DMODEL),
        order=(1, 0),
    )
    tl.store(O_block_ptr, acc, boundary_check=(0, 1))

# ------------------------------------------------------------
# Autograd Wrapper for Flash Attention
# ------------------------------------------------------------
def check_args(q, k, v, o, varlen=True, max_seqlens=None, cu_seqlens_q=None, cu_seqlens_k=None):
    assert q.dim() == k.dim() and q.dim() == v.dim()
    if varlen:
        assert q.dim() == 3
        total_q, nheads_q, head_size = q.shape
        total_k, nheads_k, _ = k.shape
        assert cu_seqlens_q is not None
        assert cu_seqlens_k is not None
        assert len(cu_seqlens_q) == len(cu_seqlens_k)
    else:
        assert q.dim() == 4
        batch, nheads_q, seqlen_q, head_size = q.shape
        _, nheads_k, seqlen_k, _ = k.shape
        assert max_seqlens > 0
    assert k.shape == v.shape
    assert q.shape[-1] == k.shape[-1] and q.shape[-1] == v.shape[-1]
    assert q.dtype == k.dtype and q.dtype == v.dtype
    assert head_size <= 256
    assert o.shape == q.shape
    assert (nheads_q % nheads_k) == 0

class _attention(torch.autograd.Function):
    @staticmethod
    def forward(ctx, q, k, v, o, cu_seqlens_q, cu_seqlens_k, max_seqlens_q, max_seqlens_k, causal=False, sm_scale=1.0, bias=None):
        if o is None:
            o = torch.empty_like(q, dtype=v.dtype)

        check_args(q, k, v, o, varlen=True, cu_seqlens_q=cu_seqlens_q, cu_seqlens_k=cu_seqlens_k)
        total_q, nheads_q, head_size = q.shape
        total_k, nheads_k, _ = k.shape
        batch = len(cu_seqlens_q) - 1
        q_strides = (0, q.stride(1), q.stride(0), q.stride(2))
        k_strides = (0, k.stride(1), k.stride(0), k.stride(2))
        v_strides = (0, v.stride(1), v.stride(0), v.stride(2))
        o_strides = (0, o.stride(1), o.stride(0), o.stride(2))

        unpadded_head_dims = {32, 64, 128, 256}
        if head_size not in unpadded_head_dims:
            padded_d_model = None
            for i in unpadded_head_dims:
                if i > head_size:
                    padded_d_model = i
                    break
            assert padded_d_model is not None
        else:
            padded_d_model = head_size

        grid = lambda META: (
            triton.cdiv(max_seqlens_q, META["BLOCK_M"]),
            nheads_q,
            batch,
        )

        encoded_softmax = None
        philox_seed = 0x1BF52
        philox_offset = 0x1D4B42

        if bias is not None:
            bias_strides = (bias.stride(0), bias.stride(1), bias.stride(2), bias.stride(3))
        else:
            bias_strides = (0, 0, 0, 0)

        attn_fwd[grid](
            q,
            k,
            v,
            bias,
            sm_scale,
            None,
            o,
            *q_strides,
            *k_strides,
            *v_strides,
            *o_strides,
            *bias_strides,
            cu_seqlens_q,
            cu_seqlens_k,
            dropout_p=0.0,
            philox_seed=philox_seed,
            philox_offset_base=philox_offset,
            encoded_softmax=encoded_softmax,
            HQ=nheads_q,
            HK=nheads_k,
            ACTUAL_BLOCK_DMODEL=head_size,
            MAX_SEQLENS_Q=max_seqlens_q,
            MAX_SEQLENS_K=max_seqlens_k,
            IS_CAUSAL=causal,
            VARLEN=True,
            BLOCK_DMODEL=padded_d_model,
            BIAS_TYPE=0 if bias is None else 1,
            ENABLE_DROPOUT=False,
            RETURN_ENCODED_SOFTMAX=False,
        )

        ctx.grid = grid
        ctx.sm_scale = sm_scale
        ctx.BLOCK_DMODEL = head_size
        ctx.causal = causal
        ctx.dropout_p = 0.0
        ctx.philox_seed = philox_seed
        ctx.philox_offset = philox_offset
        ctx.encoded_softmax = encoded_softmax
        ctx.return_encoded_softmax = False
        return o, encoded_softmax

triton_attention = _attention.apply

# ------------------------------------------------------------
# Benchmark
# ------------------------------------------------------------
import triton.testing

# Change the sequence length while keeping batch, number of heads, and head_dim fixed.
configs = [
    triton.testing.Benchmark(
        x_names=["seqlen"],
        x_vals=[64 * i for i in range(1, 9)],
        line_arg="provider",
        line_vals=["triton"],
        line_names=["Triton"],
        styles=[("blue", "-")],
        ylabel="TFLOPS",
        plot_name="flash_attention_performance_fp16",
        args={"batch": 32, "nheads": 8, "head_dim": 64},
    )
]

@triton.testing.perf_report(configs)
def benchmark_flash_attention(seqlen, provider, batch, nheads, head_dim):
    total_tokens = batch * seqlen
    q = torch.randn((total_tokens, nheads, head_dim), device='cuda', dtype=torch.float16)
    k = torch.randn((total_tokens, nheads, head_dim), device='cuda', dtype=torch.float16)
    v = torch.randn((total_tokens, nheads, head_dim), device='cuda', dtype=torch.float16)
    o = torch.empty_like(q, device='cuda', dtype=torch.float16)
    cu_seqlens_q = torch.arange(0, batch + 1, device='cuda', dtype=torch.int32) * seqlen
    cu_seqlens_k = torch.arange(0, batch + 1, device='cuda', dtype=torch.int32) * seqlen

    quantiles = [0.5, 0.2, 0.8]
    ms, min_ms, max_ms = triton.testing.do_bench(
        lambda: triton_attention(
            q, k, v, o, cu_seqlens_q, cu_seqlens_k, seqlen, seqlen, False, 1.0, None
        )[0],
        quantiles=quantiles
    )

    ops = batch * nheads * 2 * seqlen * seqlen * head_dim
    perf = lambda ms: ops / (ms * 1e-3) / 1e12  # TFLOPS
    return perf(ms), perf(max_ms), perf(min_ms)

if __name__ == "__main__":
    benchmark_flash_attention.run(show_plots=False, print_data=True)