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
	"CUSTOM_LLVM"
	"DISPLAY"
	"HOME"
	"INSTALL_JUPYTER"
	"INSTALL_TOOLS"
	"INSTALL_TRITON"
	"MAX_JOBS"
	"PIP_TRITON_VERSION"
	"ROCM_VERSION"
	"ROCR_VISIBLE_DEVICES"
	"TRITON_CPU_BACKEND"
	"USE_CCACHE"
	"WAYLAND_DISPLAY"
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
if [ -n "${USERNAME:-}" ] && [ "${USERNAME:-}" != "root" ]; then
	./setup_user.sh
fi

run_as_user ./install_software.sh

if [ "${INSTALL_TRITON:-skip}" != "skip" ]; then
	run_as_user ./setup_triton.sh "$INSTALL_TRITON"
fi
