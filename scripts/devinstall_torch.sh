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

TORCH_DIR=${WORKSPACE}/torch
TORCH_REPO=https://github.com/pytorch/pytorch.git

declare -a PIP_INSTALL_ARGS
PIP_TORCH_INDEX_URL_BASE=https://download.pytorch.org/whl

SUDO=''
if ((EUID != 0)) && command -v sudo &>/dev/null; then
	SUDO="sudo"
elif ((EUID != 0)); then
	echo "ERROR: $(basename "$0") requires root privileges or sudo." >&2
	exit 1
fi

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
	echo "Downloading Torch source code and setting up the environment for building from source..."

	if [ ! -d "$TORCH_DIR" ]; then
		echo "Cloning the Torch repo $TORCH_REPO to $TORCH_DIR ..."
		git clone "$TORCH_REPO" "$TORCH_DIR"
		if [ ! -d "$TORCH_DIR" ]; then
			echo "$TORCH_DIR not found. ERROR Cloning repository..."
			exit 1
		else
			pushd "$TORCH_DIR" 1>/dev/null || exit 1
			git submodule sync
			git submodule update --init --recursive

			if [ -n "${TORCH_GITREF:-}" ]; then
				git checkout ""
			fi

			echo "Install pre-commit hooks into your local Torch git repo (one-time)"
			pip_install pre-commit
			pre-commit install
			popd 1>/dev/null
		fi
	else
		echo "Torch repo already present, not cloning ..."
	fi
}

install_build_deps() {
	echo "Installing Torch build dependencies ..."

	pushd "$TORCH_DIR" 1>/dev/null || exit 1

	if [ -f requirements.txt ]; then
		pip_install --group dev
		pip_install mkl-static mkl-include
		make triton
	fi

	$SUDO dnf -y install numactl-devel

	if [ -n "${ROCM_VERSION:-}" ]; then
		python tools/amd_build/build_amd.py
	fi

	popd 1>/dev/null
}

install_deps() {
	echo "Installing Torch dependencies ..."
	pip_install numpy
}

install_whl() {
	echo "Installing Torch ${PIP_TORCH_INDEX_URL_BUILD:-release} from PyPI ..."

	if [ -n "${PIP_TORCH_VERSION:-}" ]; then
		echo "Using the specified version $PIP_TORCH_VERSION of torch"
		PIP_TORCH_VERSION="==$PIP_TORCH_VERSION"
	fi

	if [ -n "${PIP_TORCHVISION_VERSION:-}" ]; then
		echo "Installing the specified version $PIP_TORCHVISION_VERSION of torchvision"
		PIP_TORCHVISION_VERSION="==$PIP_TORCHVISION_VERSION"
	fi

	if [ -n "${PIP_TORCHAUDIO_VERSION:-}" ]; then
		echo "Installing the specified version $PIP_TORCHAUDIO_VERSION of torchaudio"
		PIP_TORCHAUDIO_VERSION="==$PIP_TORCHAUDIO_VERSION"
	fi

	declare -a TORCH_PACKAGES=(
		"torch${PIP_TORCH_VERSION:-}"
		"torchvision${PIP_TORCHVISION_VERSION:-}"
		"torchaudio${PIP_TORCHAUDIO_VERSION:-}"
	)

	if [ -n "${PIP_TORCH_INDEX_URL:-}" ]; then
		echo "Using the specified index, $PIP_TORCH_INDEX_URL"
		PIP_INSTALL_ARGS+=("--index-url" "$PIP_TORCH_INDEX_URL")
	elif command -v uv &>/dev/null && [ -n "${UV_TORCH_BACKEND:-}" ]; then
		echo "Using the specified uv backend, $UV_TORCH_BACKEND"
		PIP_INSTALL_ARGS+=("--torch-backend" "$UV_TORCH_BACKEND")
	elif ! command -v uv &>/dev/null && [ -n "${UV_TORCH_BACKEND:-}" ]; then
		echo "Error: UV_TORCH_BACKEND is set to $UV_TORCH_BACKEND but uv is not available."
		exit 1
	else
		# Set compute platform for torch wheel installation
		if [ -n "${ROCM_VERSION:-}" ]; then
			echo "Using the ROCm version $ROCM_VERSION backend"
			COMPUTE_PLATFORM="rocm$(get_rocm_version)"
		elif ((${TRITON_CPU_BACKEND:-0} == 1)); then
			echo "Using the CPU backend"
			COMPUTE_PLATFORM="cpu"
		elif [ -n "${CUDA_VERSION:-}" ]; then
			echo "Using the CUDA version $CUDA_VERSION backend"
			COMPUTE_PLATFORM="cu${CUDA_VERSION/[.-]/}"
		fi

		if [ -n "${COMPUTE_PLATFORM:-}" ]; then
			[[ -n "${PIP_TORCH_INDEX_URL_BUILD:-}" ]] && PIP_TORCH_INDEX_URL_BUILD="/${PIP_TORCH_INDEX_URL_BUILD}"
			PIP_TORCH_INDEX_URL="${PIP_TORCH_INDEX_URL_BASE}${PIP_TORCH_INDEX_URL_BUILD:-}/${COMPUTE_PLATFORM}"
			PIP_INSTALL_ARGS+=("--index-url" "$PIP_TORCH_INDEX_URL")
		fi
	fi

	pip_install -U --force-reinstall "${PIP_INSTALL_ARGS[@]}" "${TORCH_PACKAGES[@]}"

	# Fix up LD_LIBRARY_PATH for CUDA
	ldpretend
}

usage() {
	cat >&2 <<EOF
Usage: $(basename "$0") [COMMAND] 
    source     Download Torch's source (if needed) and install the build deps
    release    Install Torch
    nightly    Install the Torch nightly wheel
    test       Install the Torch test wheel
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
nightly | test)
	PIP_TORCH_INDEX_URL_BUILD=$COMMAND
	install_deps
	install_whl
	;;
*)
	usage
	exit 1
	;;
esac


