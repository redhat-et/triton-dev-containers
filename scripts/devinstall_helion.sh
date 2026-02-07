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

HELION_DIR=${WORKSPACE}/helion
HELION_REPO=https://github.com/pytorch/helion.git

declare -a PIP_INSTALL_ARGS

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
	echo "Downloading Helion source code and setting up the environment for building from source..."

	if [ ! -d "$HELION_DIR" ]; then
		echo "Cloning the Helion repo $HELION_REPO to $HELION_DIR ..."
		git clone "$HELION_REPO" "$HELION_DIR"
		if [ ! -d "$HELION_DIR" ]; then
			echo "$HELION_DIR not found. ERROR Cloning repository..."
			exit 1
		else
			pushd "$HELION_DIR" 1>/dev/null || exit 1
			git submodule sync
			git submodule update --init --recursive

			if [ -n "${HELION_GITREF:-}" ]; then
				git checkout "$HELION_GITREF"
			fi

			echo "Installing pre-commit hooks into your local Helion git repo (one-time)"
			pip_install pre-commit
			pre-commit install
			popd 1>/dev/null
		fi
	else
		echo "Torch repo already present, not cloning ..."
	fi
}

install_deps() {
	echo "Installing Helion dependencies ..."
	pip_install numpy

	devinstall_torch release
}

install_release() {
	echo "Installing Helion from PyPI ..."

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

	if [ -n "${PIP_HELION_INDEX_URL:-}" ]; then
		echo "Using the specified index, $PIP_HELION_INDEX_URL"
		PIP_INSTALL_ARGS+=("--index-url  $PIP_HELION_INDEX_URL")
	fi

	if [ -n "${PIP_HELION_VERSION:-}" ]; then
		echo "Installing the specified Helion version $PIP_HELION_VERSION"
		PIP_HELION_VERSION="==$PIP_HELION_VERSION"
	fi

	pip_install -U --force-reinstall "${PIP_INSTALL_ARGS[@]}" "helion${PIP_HELION_VERSION:-}"

	# Fix up LD_LIBRARY_PATH for CUDA
	ldpretend
}

usage() {
	cat >&2 <<EOF
Usage: $(basename "$0") [COMMAND] 
    source     Download Helion's source (if needed) and install the build deps
    release    Install Helion
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
	install_deps
	;;
release)
	install_deps
	install_release
	;;
*)
	usage
	exit 1
	;;
esac
