#! /bin/bash -e

trap "echo -e '\nScript interrupted. Exiting gracefully.'; exit 1" SIGINT

# Copyright (C) 2024-2025 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
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

# If you are on an OS that has the user in /etc/passwd then we can pass
# the user from the host to the pod. Otherwise we default to create the
# user inside the container.
# With podman if you aren't creating the user you need to explicitly pass
# the user as --user $(USER) to start the container as that user.

# Global Default Variables
TARGET_DEVICE=base

## Image versions
DEFAULT_CENTOS_VERSION=9
DEFAULT_IMAGE_REPO=quay.io/triton-dev-containers
DEFAULT_IMAGE_TAG=centos${DEFAULT_CENTOS_VERSION}
DEFAULT_IMAGE=${DEFAULT_IMAGE_REPO}/${TARGET_DEVICE}

# PyPi Index URLs
VLLM_INDEX_URL_BASE=https://wheels.vllm.ai

## Jupyter notebook
DEFAULT_PORT=8888

## Adds --rm to the runtime args
DELETE_ON_EXIT=false

# Container runtime global and command arguments
declare -a CTR_GLOBAL_ARGS
declare -a CTR_RUN_ARGS

# Container runtime command option arrays
declare -a CTR_DEVICE_OPTS
declare -a CTR_ENV_OPTS
declare -a CTR_PORT_OPTS
declare -a CTR_SECURITY_OPTS
declare -a CTR_USER_OPTS
declare -a CTR_VOLUME_OPTS

declare -A SRC_VOLS=(
	["GITCONFIG"]=/etc/gitconfig
	["HELION"]=/workspace/helion
	["LLVM"]=/workspace/llvm-project
	["TORCH"]=/workspace/torch
	["TRITON"]=/workspace/triton
	["USER"]=/workspace/user
	["VLLM"]=/workspace/vllm
)

declare -A VOL_PATHS=(
	["GITCONFIG"]="${HOME}/.gitconfig"
)

declare -A DEFAULT_ENV_OPTS=(
	["CENTOS_VERSION"]=9
	["CUDA_VERSION"]=12-9
	["CUDA_VISIBLE_DEVICES"]=${CUDA_VISIBLE_DEVICES:-0}
	["DISPLAY"]=${DISPLAY:-}
	["INSTALL_JUPYTER"]="false"
	["INSTALL_TOOLS"]="false"
	["INSTALL_LLVM"]="skip"
	["INSTALL_HELION"]="skip"
	["INSTALL_TORCH"]="skip"
	["INSTALL_TRITON"]="skip"
	["INSTALL_VLLM"]="skip"
	["MAX_JOBS"]=${MAX_JOBS:-$(nproc --all)}
	["PIP_HELION_VERSION"]=""
	["PIP_TORCH_INDEX_URL"]="https://download.pytorch.org/whl"
	["PIP_TORCH_VERSION"]=""
	["PIP_TRITON_VERSION"]=""
	["PIP_VLLM_COMMIT"]=""
	["PIP_VLLM_EXTRA_INDEX_URL"]=""
	["PIP_VLLM_VERSION"]=""
	["ROCM_VERSION"]=7.1.1
	["ROCR_VISIBLE_DEVICES"]=${ROCR_VISIBLE_DEVICES:-0}
	["USE_CCACHE"]=0
	["USER"]=""
	["USER_UID"]=""
	["USER_GID"]=""
	["UV_TORCH_BACKEND"]=""
	["WAYLAND_DISPLAY"]=${WAYLAND_DISPLAY:-}
	["XDG_RUNTIME_DIR"]="/tmp"
)

declare -A ENV_INSTALL_OPTS=(
	["INSTALL_JUPYTER"]="true | false"
	["INSTALL_TOOLS"]="true | false"
	["INSTALL_LLVM"]="source | skip"
	["INSTALL_HELION"]="nightly | release | source | test | skip"
	["INSTALL_TORCH"]="nightly | release | source | test | skip"
	["INSTALL_TRITON"]="release | source | skip"
	["INSTALL_VLLM"]="nightly | release | source | skip"
)

declare -A ENV_OPTS

usage() {
	cat >&2 <<EOF
Usage: ${0##*/} [OPTION]...
Options
    -c REMOTE_CONNECTION         Use the remote podman system
    -d DEVICE                    Target device [ base | cpu | cuda | rocm ] (Default: $TARGET_DEVICE)
    -i IMAGE                     Image (Default: $DEFAULT_IMAGE)
    -j MAX_JOBS                  Maximum number of jobs to use when building Triton/Helion/PyTorch/vLLM (Default: $MAX_JOBS)
    -k TARGET_STACK              Target stack [ helion | torch | triton | vllm ]
    -o OPTION=ARGUMENT           Specify a argument for an option
        CUDA_VERSION                 CUDA version (Default: ${DEFAULT_ENV_OPTS["CUDA_VERSION"]})
        CUDA_VISIBLE_DEVICES         List of NVIDIA device indices or UUIDs (i.e. 0,GPU-DEADBEEFDEADBEEF)
                                         [ ${ENV_INSTALL_OPTS["INSTALL_JUPYTER"]} ]
        INSTALL_JUPYTER              Install the Jupyter notebook server (Default: ${DEFAULT_ENV_OPTS["INSTALL_JUPYTER"]})
                                         [ ${ENV_INSTALL_OPTS["INSTALL_JUPYTER"]} ]
        INSTALL_TOOLS                Install debugging and profiling tools (i.e. NSIGHT or ROCm Systems) (Default: ${DEFAULT_ENV_OPTS["INSTALL_TOOLS"]})
                                         [ ${ENV_INSTALL_OPTS["INSTALL_TOOLS"]} ]
        INSTALL_LLVM                 Setup the container to build LLVM from source (Default: ${DEFAULT_ENV_OPTS["INSTALL_LLVM"]})
                                         [ ${ENV_INSTALL_OPTS["INSTALL_LLVM"]} ]
        INSTALL_HELION               Install or setup the container for building Helion (Default: ${DEFAULT_ENV_OPTS["INSTALL_HELION"]})
                                         [ ${ENV_INSTALL_OPTS["INSTALL_HELION"]} ]
        INSTALL_TORCH                Install or setup the container for building PyTorch (Default: ${DEFAULT_ENV_OPTS["INSTALL_TORCH"]})
                                         [ ${ENV_INSTALL_OPTS["INSTALL_TORCH"]} ]
        INSTALL_TRITON               Install or setup the container for building Triton (Default: ${DEFAULT_ENV_OPTS["INSTALL_TRITON"]})
                                         [ ${ENV_INSTALL_OPTS["INSTALL_TRITON"]} ]
        INSTALL_VLLM                 Install or setup the container for building vLLM (Default: ${DEFAULT_ENV_OPTS["INSTALL_VLLM"]})
                                         [ ${ENV_INSTALL_OPTS["INSTALL_VLLM"]} ]
        PIP_HELION_VERSION           Helion wheel version
        PIP_TORCH_INDEX_URL          http://<url> (Default: ${DEFAULT_ENV_OPTS["PIP_TORCH_INDEX_URL"]})
        PIP_TORCH_VERSION            Torch wheel version
        PIP_TRITON_VERSION           Triton wheel version
        PIP_VLLM_COMMIT              vLLM git commit hash for wheel install ($VLLM_INDEX_URL_BASE/<commit>)
        PIP_VLLM_EXTRA_INDEX_URL     http://<url> [Not used with PIP_VLLM_COMMIT] (Default: $VLLM_INDEX_URL_BASE)
        PIP_VLLM_VERSION             vLLM wheel version
        ROCM_VERSION                 ROCm version (Default: ${DEFAULT_ENV_OPTS["ROCM_VERSION"]})
        ROCR_VISIBLE_DEVICES         List of AMD device indices or UUIDs (i.e. 0,GPU-DEADBEEFDEADBEEF)
        USE_CCACHE                   Enable ccache [ 0 | 1 ] (Default: ${DEFAULT_ENV_OPTS["USE_CCACHE"]})
        UV_TORCH_BACKEND             Framework version: [ cu${DEFAULT_ENV_OPTS["CUDA_VERSION"]//-/} | rocm${DEFAULT_ENV_OPTS["ROCM_VERSION"]%.*} | cpu ]
    -p [ AUTO | PORT ]           Expose the specified port for the Jupyter notebook server (AUTO: $DEFAULT_PORT)
    -r                           Remove the container on exit
    -s SOURCE=PATH               Local source directories to mount as volumes
        GITCONFIG                    /path/to/gitconfig (Default: ${VOL_PATHS["GITCONFIG"]})
        HELION                       /path/to/helion/source
        LLVM                         /path/to/llvm/source
        TORCH                        /path/to/torch/source
        TRITON                       /path/to/triton/source
        USER                         /path/to/user/source
        VLLM                         /path/to/vllm/source
    -t IMAGE_TAG                 Image tag (Default: $DEFAULT_IMAGE_TAG)
    -u USERNAME                  Username to use inside the image
    -h                           Print usage
    -v                           Verbose
EOF
}

set_env_opt() {
	local key=$1
	local value=$2

	if [[ ! "${!ENV_OPTS[*]}" =~ $key ]]; then
		if [[ "${!DEFAULT_ENV_OPTS[*]}" =~ $key ]]; then
			if [[ "${!ENV_INSTALL_OPTS[*]}" =~ $key ]]; then
				if [[ ! "${ENV_INSTALL_OPTS[$key]}" =~ $value ]]; then
					echo "Bad install option, $value, for $key, can only be ${ENV_INSTALL_OPTS[$key]}"
					exit 1
				fi
			fi

			ENV_OPTS[$key]="$value"
			CTR_ENV_OPTS+=("-e $key=$value")
		else
			echo "Unknown env option, $key."
			exit 1
		fi
	fi
}

set_container_runtime() {
	if command -v podman &>/dev/null; then
		CTR_CMD=podman
	elif command -v docker &>/dev/null; then
		CTR_CMD=docker
	else
		echo "Could not find the podman or docker container runtime."
		echo "Please install one of them."
		exit 1
	fi
}

setup_volumes() {
	local selinux_flag

	# Set selinux volume flag if enforcing
	if command -v getenforce &>/dev/null && [ "$(getenforce 2>/dev/null)" == "Enforcing" ]; then
		selinux_flag=:z
	fi

	# Custom source code path(s)
	for vol in "${!SRC_VOLS[@]}"; do
		vol_path="${VOL_PATHS[$vol]:-}"
		if [ -n "${vol_path:-}" ]; then
			if [ -e "${vol_path}" ]; then
				CTR_VOLUME_OPTS+=("-v ${vol_path}:${SRC_VOLS[$vol]}${selinux_flag:-}")
				if [ "$vol" != "USER" ] && [ "$vol" != "GITCONFIG" ]; then
					set_env_opt "INSTALL_${vol^^}" source
				fi
			elif [ "$vol" != "GITCONFIG" ]; then
				echo "Specified $vol path, $vol_path, does not exist."
				exit 1
			fi
		fi
	done

	# User management for non-Mac OS's
	if [ "$(uname -s)" != "Darwin" ] && ! getent passwd "$USER" >/dev/null && [ -n "${USERNAME:-}" ]; then
		CTR_VOLUME_OPTS+=(
			"-v /etc/passwd:/etc/passwd:ro"
			"-v /etc/group:/etc/group:ro"
		)
	fi
}

set_device_opts() {
	case ${TARGET_DEVICE,,} in
	rocm)
		CTR_DEVICE_OPTS+=(
			"--device=/dev/kfd"
			"--device=/dev/dri"
		)
		CTR_SECURITY_OPTS+=(
			"--cap-add=SYS_PTRACE"
			"--group-add=render"
			"--group-add=video"
			"--ipc=host"
			"--security-opt seccomp=unconfined"
		)

		set_env_opt ROCM_VERSION "${DEFAULT_ENV_OPTS["ROCM_VERSION"]}"
		set_env_opt ROCR_VISIBLE_DEVICES "${DEFAULT_ENV_OPTS["ROCR_VISIBLE_DEVICES"]}"
		IMAGE_TAG="${ENV_OPTS["ROCM_VERSION"]}"-${DEFAULT_IMAGE_TAG}
		;;
	cuda)
		if command -v nvidia-ctk >/dev/null 2>&1 && nvidia-ctk cdi list | grep -q "nvidia.com/gpu=all"; then
			CTR_DEVICE_OPTS+=("--device nvidia.com/gpu=all")
		else
			CTR_DEVICE_OPTS+=("--runtime=nvidia --gpus=all")
		fi

		CTR_SECURITY_OPTS+=("--security-opt label=disable")

		if [ "${INSTALL_TOOLS:-}" = "true" ]; then
			CTR_SECURITY_OPTS+=(
				"--privileged"
				"--cap-add=SYS_ADMIN"
			)

			if [ -n "${DEFAULT_ENV_OPTS["DISPLAY"]:-}" ] && [ -n "${DEFAULT_ENV_OPTS["WAYLAND_DISPLAY"]:-}" ]; then
				set_env_opt DISPLAY "${DEFAULT_ENV_OPTS["DISPLAY"]}"
				set_env_opt WAYLAND_DISPLAY "${DEFAULT_ENV_OPTS["WAYLAND_DISPLAY"]}"
				set_env_opt XDG_RUNTIME_DIR "${DEFAULT_ENV_OPTS["XDG_RUNTIME_DIR"]}"

				CTR_VOLUME_OPTS+=(
					"-v ${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}:/tmp/${WAYLAND_DISPLAY}:ro"
				)
			else
				echo "WARNING: No DISPLAY or WAYLAND_DISPLAY configured"
			fi
		fi

		set_env_opt CUDA_VERSION "${DEFAULT_ENV_OPTS["CUDA_VERSION"]}"
		set_env_opt CUDA_VISIBLE_DEVICES "${DEFAULT_ENV_OPTS["CUDA_VISIBLE_DEVICES"]}"
		IMAGE_TAG=${ENV_OPTS["CUDA_VERSION"]}-${DEFAULT_IMAGE_TAG}
		;;
	esac
}

set_user_args() {
	if [ -z "${USERNAME:-}" ] && [ "$(whoami)" != "root" ]; then
		USERNAME=$(whoami)
	fi

	if [ -n "${USERNAME:-}" ] && [ "${USERNAME:-}" != "root" ]; then
		set_env_opt USER "$USERNAME"
		set_env_opt USER_UID "$(id -u "$USER")"
		set_env_opt USER_GID "$(id -g "$USER")"
	elif [ "$(basename "$CTR_CMD")" = "docker" ]; then
		CTR_USER_OPTS+=(
			"--user $(id -u):$(id -g)"
		)
	elif [ "$(basename "$CTR_CMD")" = "podman" ]; then
		CTR_USER_OPTS+=(
			"--user $USER"
		)
	fi
}

##
## MAIN
##

while getopts "c:d:i:j:k:o:p:rs:t:u:hv" opt; do
	case "$opt" in
	c)
		REMOTE_CONNECTION=$OPTARG
		;;
	d)
		TARGET_DEVICE=$OPTARG
		;;
	i)
		IMAGE="$OPTARG"
		;;
	j)
		set_env_opt MAX_JOBS "$OPTARG"
		;;
	k)
		TARGET_STACK=$OPTARG
		;;
	o)
		SUBOPT="${OPTARG/=*/}"
		set_env_opt "${SUBOPT^^}" "${OPTARG/*=/}"
		;;
	p)
		set_env_opt INSTALL_JUPYTER true
		if [ "${OPTARG^^}" = "AUTO" ]; then
			JUPYTER_NOTEBOOK_PORT="$DEFAULT_PORT"
		else
			JUPYTER_NOTEBOOK_PORT="$OPTARG"
		fi
		;;
	r)
		DELETE_ON_EXIT=true
		;;
	s)
		SUBOPT="${OPTARG/=*/}"
		if [[ "${!SRC_VOLS[*]}" =~ ${SUBOPT^^} ]]; then
			VOL_PATHS["${SUBOPT^^}"]="${OPTARG/*=/}"
		else
			echo "Unknown source path, $OPTARG"
			exit 1
		fi
		;;
	t)
		IMAGE_TAG="$OPTARG"
		;;
	u)
		USERNAME="$OPTARG"
		;;
	h)
		usage
		exit 0
		;;
	v)
		set -x
		;;
	*)
		echo "Unknown option, $opt."
		exit 1
		;;
	esac
done
shift $((OPTIND - 1))

##
## Command Configuration
##

# Container Runtime
set_container_runtime

# Setup Volumes
setup_volumes

# Device specific arguments (AMD, NVIDIA, etc)
set_device_opts

# Runtime Arguments
if [ "$(basename "$CTR_CMD")" = "podman" ]; then
	CTR_SECURITY_OPTS+=("--userns=keep-id")
fi

# Jupyter Notebook
if [ "${INSTALL_JUPYTER:-}" = "true" ]; then
	CTR_PORT_OPTS+=("-p ${JUPYTER_NOTEBOOK_PORT:-$DEFAULT_PORT}:${JUPYTER_NOTEBOOK_PORT:-$DEFAULT_PORT}")
	set_env_opt INSTALL_JUPYTER "$INSTALL_JUPYTER"
	set_env_opt NOTEBOOK_PORT "${JUPYTER_NOTEBOOK_PORT:-$DEFAULT_PORT}"
fi

# User args
set_user_args

# Set stack options
if [ -n "${TARGET_STACK:-}" ]; then
	case ${TARGET_STACK,,} in
	helion)
		set_env_opt INSTALL_HELION "source"
		set_env_opt INSTALL_TORCH "release"
		;;
	torch)
		set_env_opt INSTALL_TORCH "source"
		;;
	triton)
		set_env_opt INSTALL_TORCH "release"
		set_env_opt INSTALL_TRITON "source"
		;;
	vllm)
		set_env_opt INSTALL_VLLM "source"
		;;
	*)
		echo "Unknown stack, $TARGET_STACK"
		exit 1
		;;
	esac
fi

if [ -n "${REMOTE_CONNECTION:-}" ]; then
	CTR_GLOBAL_ARGS+=("-r" "-c $REMOTE_CONNECTION")
fi

if [ "${DELETE_ON_EXIT:-}" = "true" ]; then
	CTR_RUN_ARGS+=("--rm")
fi

IMAGE=${IMAGE:-${DEFAULT_IMAGE_REPO}/${TARGET_DEVICE}:${IMAGE_TAG:-${DEFAULT_IMAGE_TAG}}}

# Build and cleanup the run command
RUN_CMD="$CTR_CMD \
	${CTR_GLOBAL_ARGS[*]:-} \
	run \
	-ti \
	${CTR_RUN_ARGS[*]:-} \
	${CTR_ENV_OPTS[*]:-} \
	${CTR_DEVICE_OPTS[*]:-} \
	${CTR_PORT_OPTS:-} \
	${CTR_SECURITY_OPTS[*]:-} \
	${CTR_VOLUME_OPTS[*]:-} \
	${IMAGE} \
	bash"
RUN_CMD=$(echo "$RUN_CMD" | tr -d '\t\n' | tr -s '\s')

echo "Running container image: $IMAGE with $CTR_CMD"
echo "$RUN_CMD"
$RUN_CMD
