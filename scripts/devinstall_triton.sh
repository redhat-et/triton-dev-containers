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

WORKSPACE=${WORKSPACE:-${HOME}}

TRITON_DIR=${WORKSPACE}/triton
TRITON_REPO=https://github.com/triton-lang/triton.git

# Remove the dashes or periods from the CUDA version, e.g. 128 from 12-8
get_cuda_version() {
	echo "${CUDA_VERSION//[.-]/}"
}

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

			if [ -n "${TRITON_GITREF:-}" ]; then
				git checkout "$TRITON_GITREF"
			fi

			git submodule sync
			git submodule update --init --recursive

			echo "Install pre-commit hooks into your local Triton git repo (one-time)"
			pip_install pre-commit
			pre-commit install
			popd 1>/dev/null
		fi
	else
		echo "Triton repo already present, not cloning ..."
	fi

	echo "Setting LLVM_COMMIT_HASH in ${HOME}/.bashrc.d/00-triton_llvm_commit_hash.sh ..."
	tee "${HOME}/.bashrc.d/00-triton_llvm_commit_hash.sh" <<EOF
# Set LLVM to the Triton LLVM commit hash
export LLVM_COMMIT_HASH=$(cat "${TRITON_DIR}/cmake/llvm-hash.txt")
EOF
}

install_build_deps() {
	echo "Installing Triton build dependencies ..."
	pushd "$TRITON_DIR" 1>/dev/null || exit 1

	make dev-install-requires

	if ((${USE_CCACHE:-0} != 0)); then
		echo "Setting triton ccache environment variables in ${HOME}/.bashrc.d/00-triton_ccache.sh ... "
		tee "${HOME}/.bashrc.d/00-triton_ccache.sh" <<EOF
# Use ccache when building Triton
export TRITON_BUILD_WITH_CCACHE=true
export TRITON_CACHE_DIR=${WORKSPACE}/.triton/cache
EOF
	fi

	popd 1>/dev/null
}

install_deps() {
	echo "Installing Triton dependencies ..."
	pip_install cmake ctypeslib2 matplotlib ninja \
		numpy pandas pybind11 pytest pyyaml scipy tabulate wheel

	if [ "${INSTALL_TORCH:-}" != "source" ]; then
		if [ -n "${INSTALL_TORCH:-}" ] && [ "${INSTALL_TORCH}" != "skip" ]; then
			echo "Installing Torch $INSTALL_TORCH as a dependency ..."
			devinstall_torch "${INSTALL_TORCH}"
		else
			echo "Installing Torch as a dependency ..."
			devinstall_torch release
		fi
	fi
}

install_whl() {
	local -a pip_install_args

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
			UV_TORCH_BACKEND="cu$(get_cuda_version)"
		else
			echo "Using the torch auto backend"
			UV_TORCH_BACKEND=auto
		fi

		pip_install_args+=("--torch-backend" "$UV_TORCH_BACKEND")
	elif ! command -v uv &>/dev/null && [ -n "${UV_TORCH_BACKEND:-}" ]; then
		echo "Error: UV_TORCH_BACKEND is set to $UV_TORCH_BACKEND but uv is not available."
		exit 1
	fi

	if [ -n "${PIP_TRITON_VERSION:-}" ]; then
		echo "Specified Triton version $PIP_TRITON_VERSION"
		PIP_TRITON_VERSION="==$PIP_TRITON_VERSION"
	fi

	pip_install -U --force-reinstall "${pip_install_args[@]}" "triton${PIP_TRITON_VERSION:-}"

	# Fix up LD_LIBRARY_PATH for CUDA
	ldpretend
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
