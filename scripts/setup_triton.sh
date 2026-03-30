#! /bin/bash -e

trap "echo -e '\nScript interrupted. Exiting gracefully.'; exit 1" SIGINT

# Copyright (C) 2024-2026 Red Hat, Inc.
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

declare -a PIP_INSTALL_ARGS
PIP_TORCH_INDEX_URL_BASE=https://download.pytorch.org/whl

WORKSPACE=${WORKSPACE:-${HOME}}

TRITON_DIR=${WORKSPACE}/triton
TRITON_REPO=https://github.com/triton-lang/triton.git

# Extract the major.minor version from ROCM_VERSION, e.g. 6.4 from 6.4.4
get_rocm_version() {
	[[ "$ROCM_VERSION" =~ ^([0-9]+\.[0-9]+) ]] && echo "${BASH_REMATCH[1]}" ||
		echo "$ROCM_VERSION"
}

pip_install() {
	if command -v uv &>/dev/null; then
		uv pip install "$@"
	else
		pip install "$@"
	fi
}

setup_src() {
	echo "Downloading Triton source code and setting up the environment for building from source..."
	if ((${TRITON_CPU_BACKEND:-0} == 1)); then
		TRITON_DIR=${WORKSPACE}/triton-cpu
		TRITON_REPO=https://github.com/triton-lang/triton-cpu.git
	fi

	if [ ! -d "$TRITON_DIR" ]; then
		echo "Cloning the triton repo $TRITON_REPO to $TRITON_DIR ..."
		git clone "$TRITON_REPO" "$TRITON_DIR"
		if [ ! -d "$TRITON_DIR" ]; then
			echo "$TRITON_DIR not found. ERROR Cloning repository..."
			exit 1
		else
			pushd "$TRITON_DIR" 1>/dev/null || exit 1
			git submodule sync
			git submodule update --init --recursive

			if [ -n "${TRITON_GITREF:-}" ]; then
				git checkout "$TRITON_GITREF"
			fi

			echo "Install pre-commit hooks into your local Triton git repo (one-time)"
			pip_install pre-commit
			pre-commit install
			popd 1>/dev/null
		fi

		echo "Setting the LLVM_GITREF as specified by Triton ..."
		tee -a "${HOME}/.bashrc" <<EOF

# Setting the LLVM Triton gitref
export LLVM_GITREF=$(cat "${TRITON_DIR}/cmake/llvm-hash.txt")
EOF

	else
		echo "Triton repo already present, not cloning ..."
	fi

}

install_build_deps() {
	echo "Installing Triton build dependencies ..."
	pushd "$TRITON_DIR" 1>/dev/null || exit 1

	make dev-install-requires

	if ((${USE_CCACHE:-0} != 0)); then
		tee -a "${HOME}"/.bashrc <<EOF

# Use ccache when building Triton
export TRITON_BUILD_WITH_CCACHE=true
export TRITON_CACHE_DIR=${WORKSPACE}/.triton/cache
EOF
	fi

	popd 1>/dev/null

	if [ "${CUSTOM_LLVM:-false}" = "true" ] && [ -d "/llvm-project/install" ]; then
		echo "Using custom LLVM from /llvm-project/install"
		tee -a "${HOME}/.bashrc" <<EOF

# Using custom LLVM
export LLVM_BUILD_DIR="/llvm-project/install"
export LLVM_INCLUDE_DIRS="/llvm-project/install/include"
export LLVM_LIBRARY_DIR="/llvm-project/install/lib"
export LLVM_SYSPATH="/llvm-project/install"
EOF
	fi
}

install_deps() {
	echo "Installing Triton dependencies ..."
	pip_install cmake ctypeslib2 matplotlib ninja \
		numpy pandas pybind11 pytest pyyaml scipy tabulate wheel

	if [ -n "${TORCH_VERSION:-}" ]; then
		echo "Installing the specified version $TORCH_VERSION of torch"
		PIP_TORCH_VERSION="==$TORCH_VERSION"
	fi

	if [ -n "${ROCM_VERSION:-}" ]; then
		echo "Installing torch for ROCm version $ROCM_VERSION"
		pip_install "torch${PIP_TORCH_VERSION:-}" \
			--index-url "${PIP_TORCH_INDEX_URL_BASE}/rocm$(get_rocm_version)"
	elif ((${TRITON_CPU_BACKEND:-0} == 1)); then
		echo "Installing torch for CPU"
		pip_install "torch${PIP_TORCH_VERSION:-}" \
			--index-url "${PIP_TORCH_INDEX_URL_BASE}/cpu"
	elif [ -n "${CUDA_VERSION:-}" ]; then
		echo "Installing torch for CUDA version $CUDA_VERSION"
		pip_install "torch${PIP_TORCH_VERSION:-}" \
			--index-url "${PIP_TORCH_INDEX_URL_BASE}/cu${CUDA_VERSION/[.-]/}"
	else
		echo "Installing torch ..."
		pip_install "torch${PIP_TORCH_VERSION:-}"
	fi
}

install_whl() {
	echo "Installing Triton from PyPI ..."

	if command -v uv &>/dev/null; then
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

	if [ -n "${PIP_TRITON_VERSION:-}" ]; then
		echo "Specified Triton version $PIP_TRITON_VERSION"
		PIP_TRITON_VERSION="==$PIP_TRITON_VERSION"
	fi

	pip_install "${PIP_INSTALL_ARGS[@]}" "triton${PIP_TRITON_VERSION:-}"

	# Fix up LD_LIBRARY_PATH for CUDA
	"${WORKSPACE}"/ldpretend.sh
}

usage() {
	cat >&2 <<EOF
Usage: $(basename "$0") [COMMAND]
    source     Download Triton's source (if needed) and install the build deps
    release    Install Triton
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
	install_deps
	;;
release)
	install_deps
	install_whl
	;;
*)
	usage
	exit 1
	;;
esac
