#! /bin/bash -e

trap "echo -e '\nScript interrupted. Exiting gracefully.'; exit 1" SIGINT

# Copyright (C) 2024-2025 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

WORKSPACE=${WORKSPACE:-${HOME}}

VLLM_REPO=https://github.com/vllm-project/vllm.git
VLLM_DIR="${WORKSPACE}/vllm"

declare -a PIP_INSTALL_ARGS
PIP_VLLM_INDEX_URL_BASE=https://wheels.vllm.ai

pip_install() {
	if command -v uv &>/dev/null; then
		uv pip install "$@"
	else
		pip install "$@"
	fi
}

# Extract the major.minor version from ROCM_VERSION, e.g. 6.4 from 6.4.4
get_rocm_version() {
	[[ "$ROCM_VERSION" =~ ^([0-9]+\.[0-9]+) ]] && echo "${BASH_REMATCH[1]}" ||
		echo "$ROCM_VERSION"
}

setup_src() {
	if [ ! -d "${VLLM_DIR}" ]; then
		echo "Cloning the vLLM repo $VLLM_REPO to $VLLM_DIR ..."
		git clone "$VLLM_REPO" "$VLLM_DIR"

		if [ ! -d "$VLLM_DIR" ]; then
			echo "$VLLM_DIR not found. ERROR Cloning repository..."
			exit 1
		else
			pushd "$VLLM_DIR" 1>/dev/null || exit 1
			git submodule sync
			git submodule update --init --recursive

			if [ -n "${VLLM_GITREF:-}" ]; then
				git checkout "$VLLM_GITREF"
			fi

			echo "Install pre-commit hooks into your local vLLM git repo (one-time)"
			pip_install pre-commit
			pre-commit install
			popd 1>/dev/null
		fi
	else
		echo "vLLM repo already present, not cloning ..."
	fi
}

install_build_deps() {
	pushd "$VLLM_DIR" 1>/dev/null || exit 1

	if [ "${INSTALL_TORCH:-}" = "source" ]; then
		echo "Using existing torch source build ..."
		python use_existing_torch.py
	else
		echo "Installing Torch as a vLLM dependency ..."
		devinstall_torch release
	fi

	if [ -n "${CUDA_VERSION:-}" ]; then
		VLLM_TARGET_DEVICE=cuda

		if [ -e requirements/cuda.txt ]; then
			echo "Installing vLLM CUDA build dependencies ..."
			pip_install --prerelease=allow -r requirements/cuda.txt
		fi
	elif [ -n "${ROCM_VERSION:-}" ]; then
		VLLM_TARGET_DEVICE=rocm

		pip_install --upgrade numba \
			scipy \
			"huggingface-hub[cli,hf_transfer]" \
			setuptools_scm

		pip_install "numpy<2"

		if [ -e requirements/rocm.txt ]; then
			echo "Installing vLLM ROCm build dependencies ..."
			pip_install --prerelease=allow -r requirements/rocm.txt
		fi
	elif [ "${TRITON_CPU_BACKEND:-0}" -eq 1 ]; then
		VLLM_TARGET_DEVICE=cpu

		if [ -e requirements/cpu.txt ]; then
			echo "Installing vLLM CPU build dependencies ..."
			pip_install --prerelease=allow -r requirements/cpu.txt
		fi
	fi

	if [ -f requirements/build.txt ]; then
		echo "Installing vLLM build dependencies ..."
		pip_install --prerelease=allow -r requirements/build.txt
	fi

	popd 1>/dev/null

	echo "Set the target device for vLLM build ..."
	tee -a "${HOME}/.bashrc" <<EOF

# Target device for vLLM build
export VLLM_TARGET_DEVICE=$VLLM_TARGET_DEVICE
EOF
	echo "Run 'source ${HOME}/.bashrc' before building vLLM"
}

install_whl() {
	echo "Installing vLLM from PyPI ..."

	if [ -n "${PIP_VLLM_EXTRA_INDEX_URL:-}" ]; then
		echo "Using the specified index, $PIP_VLLM_EXTRA_INDEX_URL"
		PIP_INSTALL_ARGS+=("--index-url" "$PIP_VLLM_EXTRA_INDEX_URL")
	elif [ -n "${VLLM_COMMIT:-}" ]; then
		echo "Using the build from commit $VLLM_COMMIT ..."
		PIP_VLLM_EXTRA_INDEX_URL="--extra-index-url ${PIP_VLLM_INDEX_URL_BASE}/${VLLM_COMMIT}"
	elif command -v uv &>/dev/null; then
		if [ -n "${UV_TORCH_BACKEND:-}" ]; then
			echo "Using the specified uv backend, $UV_TORCH_BACKEND"
		elif [ -n "${ROCM_VERSION:-}" ]; then
			echo "Using the torch ROCm version $ROCM_VERSION backend"
			UV_TORCH_BACKEND="rocm$(get_rocm_version)"
		elif ((${TRITON_CPU_BACKEND:-0} == 1)); then
			echo "Using the torch CPU backend"
			UV_TORCH_BACKEND=cpu
		elif [ -n "${CUDA_VERSION:-}" ]; then
			echo "Using the torch CUDA version $CUDA_VERSION backend"
			UV_TORCH_BACKEND="cu${CUDA_VERSION/[.-]/}"
		else
			echo "Using the torch auto backend"
			UV_TORCH_BACKEND=auto
		fi

		PIP_INSTALL_ARGS+=("--torch-backend" "$UV_TORCH_BACKEND")
	elif ! command -v uv &>/dev/null && [ -n "${UV_TORCH_BACKEND:-}" ]; then
		echo "Error: UV_TORCH_BACKEND is set to $UV_TORCH_BACKEND but uv is not available."
		exit 1
	fi

	if [ -n "${PIP_VLLM_VERSION:-}" ]; then
		echo "Installing specified version $PIP_VLLM_VERSION"
		PIP_VLLM_VERSION="==$PIP_VLLM_VERSION"
	fi

	pip_install -U --force-reinstall "${PIP_INSTALL_ARGS[@]}" "vllm${PIP_VLLM_VERSION:-}" \

	# Fix up LD_LIBRARY_PATH for CUDA
	ldpretend
}

usage() {
	cat >&2 <<EOF
Usage: $(basename "$0") [COMMAND]
    source     Download vLLM's source (if needed) and install the build deps
    release    Install vLLM
    nightly    Install the vLLM nightly wheel
EOF
}

##
## Main
##

if [ $# -ne 1 ]; then
	usage
	exit 1
fi

COMMAND=${1,,}

case $COMMAND in
source)
	setup_src
	install_build_deps
	;;
release)
	install_whl
	;;
nightly)
	PIP_VLLM_EXTRA_INDEX_URL="--extra-index-url ${PIP_VLLM_INDEX_URL_BASE}/nightly"
	install_whl
	;;
*)
	usage
	exit 1
	;;
esac
