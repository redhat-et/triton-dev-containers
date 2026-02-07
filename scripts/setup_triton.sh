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

setup_src() {
	if [ "${TRITON_CPU_BACKEND:-0}" -eq 1 ]; then
		TRITON_DIR=${WORKSPACE}/triton-cpu
		TRITON_REPO=https://github.com/triton-lang/triton-cpu.git
	else
		TRITON_DIR=${WORKSPACE}/triton
		TRITON_REPO=https://github.com/triton-lang/triton.git
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
			uv pip install pre-commit
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
	echo "Installing triton build dependencies ..."
	pushd "$TRITON_DIR" 1>/dev/null || exit 1

	if [ -f python/requirements.txt ]; then
		uv pip install -r python/requirements.txt
	fi

	if [ ${USE_CCACHE:-0} -ne 0 ]; then
		tee -a "${HOME}"/.bashrc <<EOF

# Use ccache when building Triton
export TRITON_BUILD_WITH_CCACHE=true
export TRITON_CACHE_DIR=${WORKSPACE}/.triton/cache
EOF
	fi

	popd 1>/dev/null
}

install_deps() {
	echo "Installing triton dependencies ..."
	uv pip install cmake ctypeslib2 matplotlib ninja \
		numpy pandas pybind11 pytest pyyaml scipy tabulate wheel
}

install_release() {
	if [ -n "${UV_TORCH_BACKEND:-}" ]; then
		echo "Using specified torch backend, $UV_TORCH_BACKEND"
	elif [ -n "${ROCM_VERSION:-}" ]; then
		TORCH_ROCM_VERSION=$(echo "$ROCM_VERSION" | sed -e 's/\([0-9]\.[0-9]\).*/\1/')

		echo "Using the torch ROCm version $TORCH_ROCM_VERSION backend"
		UV_TORCH_BACKEND="rocm${TORCH_ROCM_VERSION}"
	elif [ ${TRITON_CPU_BACKEND:-0} -eq 1 ]; then
		echo "Using the torch CPU backend"
		UV_TORCH_BACKEND=cpu
	elif [ -n "${CUDA_VERSION:-}" ]; then
		TORCH_CUDA_VERSION=$(echo "$CUDA_VERSION" | sed -e 's/\([0-9]*\)[.-]\([0-9]\)/\1\2/')

		echo "Using the torch CUDA version $TORCH_CUDA_VERSION backend"
		UV_TORCH_BACKEND="cu${TORCH_CUDA_VERSION}"
	else
		echo "Using the torch auto backend"
		UV_TORCH_BACKEND=auto
	fi

	if [ -n "${PIP_TRITON_VERSION:-}" ]; then
		echo "Specified Triton version $PIP_TRITON_VERSION"
		PIP_TRITON_VERSION="==$PIP_TRITON_VERSION"
	fi

	uv pip install triton${PIP_TRITON_VERSION:-} \
		--torch-backend="$UV_TORCH_BACKEND"

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
	echo "Setting up the environment for building Triton from source..."
	setup_src
	install_build_deps
	install_deps
	;;
release)
	echo "Installing Triton ..."
	install_release
	install_deps
	;;
*)
	usage
	exit 1
	;;
esac
