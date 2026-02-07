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

declare -a SAVE_VARS=(
	"CUDA_VERSION"
	"DISPLAY"
	"INSTALL_JUPYTER"
	"INSTALL_LLVM"
	"INSTALL_TOOLS"
	"INSTALL_TORCH"
	"INSTALL_TRITON"
	"MAX_JOBS"
	"PIP_TRITON_VERSION"
	"ROCM_VERSION"
	"ROCR_VISIBLE_DEVICES"
	"TORCH_VERSION"
	"TRITON_CPU_BACKEND"
	"TRITON_GITREF"
	"USE_CCACHE"
	"UV_TORCH_BACKEND"
	"WAYLAND_DISPLAY"
	"WORKSPACE"
	"XDG_RUNTIME_DIR"
)

run_as_user() {
	if [ -n "${USERNAME:-}" ] && [ "${USERNAME:-}" != "root" ]; then
		# Create comma separated list for runuser
		printf -v ENV_LIST '%s,' "${SAVE_VARS[@]}"
		runuser -w "${ENV_LIST%,}" -u "$USERNAME" -- "$@"
	else
		"$@"
	fi
}

##
## Main
##

echo "Setting up the container environment ..."

devcreate_user

run_as_user devinstall_software

if [ "${INSTALL_TRITON:-skip}" != "skip" ]; then
	run_as_user devinstall_triton "$INSTALL_TRITON"
fi

if [ "${INSTALL_LLVM:-skip}" != "skip" ]; then
	run_as_user devinstall_llvm "$INSTALL_LLVM"
fi

if [ "${INSTALL_TORCH:-skip}" != "skip" ]; then
	run_as_user devinstall_torch "$INSTALL_TORCH"
fi
