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

LLVM_DIR=${WORKSPACE}/llvm-project
LLVM_REPO=https://github.com/llvm/llvm-project.git
LLVM_BUILD_PATH=$LLVM_DIR/build

pip_install() {
	if command -v uv &>/dev/null; then
		uv pip install "$@"
	else
		pip install "$@"
	fi
}

setup_src() {
	echo "Downloading LLVM source code and setting up the environment for building from source..."

	if [ ! -d "$LLVM_DIR" ]; then
		echo "Cloning the LLVM Project repo $LLVM_REPO to $LLVM_DIR ..."
		git clone "$LLVM_REPO" "$LLVM_DIR"
		if [ ! -d "$LLVM_DIR" ]; then
			echo "$LLVM_DIR not found. ERROR Cloning repository..."
			exit 1
		else
			pushd "$LLVM_DIR" 1>/dev/null || exit 1
			git fetch origin

			# shellcheck source=/dev/null
			[ -f "${HOME}"/.bashrc ] && source "${HOME}"/.bashrc

			if [ -n "${LLVM_GITREF:-}" ]; then
				git checkout "$LLVM_GITREF"
			fi
			popd 1>/dev/null
		fi
	else
		echo "LLVM repo already present, not cloning ..."
	fi

	echo "Adding LLVM_BUILD_PATH to ${HOME}/.bashrc ..."
	echo "export LLVM_BUILD_PATH=$LLVM_BUILD_PATH" >>"${HOME}/.bashrc"
	echo "Run 'source ${HOME}/.bashrc' to update the current shell"
}

install_build_deps() {
	pushd "$LLVM_DIR" 1>/dev/null || exit 1
	if [ -f mlir/python/requirements.txt ]; then
		echo "Installing LLVM build dependencies ..."
		pip_install -r mlir/python/requirements.txt
	fi
	popd 1>/dev/null
}

usage() {
	cat >&2 <<EOF
Usage: $(basename "$0") [COMMAND]
    source    Download LLVM's source (if needed) and install the build deps
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
*)
	usage
	exit 1
	;;
esac
