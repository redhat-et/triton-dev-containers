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
CENTOS_VERSION=10
CUDA_VERSION=13-0
ROCM_VERSION=7.1.1

DEFAULT_IMAGE_REPO=quay.io/triton-dev-containers
DEFAULT_IMAGE_TAG=centos${CENTOS_VERSION}
DEFAULT_IMAGE=${DEFAULT_IMAGE_REPO}/${TARGET_DEVICE}

GITCONFIG_PATH="${HOME}/.gitconfig"
CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-0}
ROCR_VISIBLE_DEVICES=${ROCR_VISIBLE_DEVICES:-0}

# PyPi Index URLs
PIP_TORCH_INDEX_URL=https://download.pytorch.org/whl
VLLM_INDEX_URL_BASE=https://wheels.vllm.ai

## Jupyter notebook
INSTALL_JUPYTER=false
DEFAULT_PORT=8888

## Image modifiers
MAX_JOBS=${MAX_JOBS:-$(nproc --all)}
USE_CCACHE=0

## Adds --rm to the runtime args
DELETE_ON_EXIT=false

# Container runtime command option arrays
declare -a CTR_ENV_OPTS
declare -a CTR_DEVICE_OPTS
declare -a CTR_SECURITY_OPTS
declare -a CTR_VOLUME_OPTS

declare -A VOL_DIRS=(
	["LLVM"]=llvm-project
	["HELION"]=helion
	["TRITON"]=triton
	["TORCH"]=torch
	["VLLM"]=vllm
	["USER"]=user
)

declare -A OPTS=(
	["INSTALL_JUPYTER"]="true | false"
	["INSTALL_TOOLS"]="true | false"
	["INSTALL_LLVM"]="source | skip"
	["INSTALL_HELION"]="nightly | release | source | test | skip"
	["INSTALL_TORCH"]="nightly | release | source | test | skip"
	["INSTALL_TRITON"]="release | source | skip"
	["INSTALL_VLLM"]="nightly | release | source | skip"
)

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
        CUDA_VERSION                 CUDA version (Default: $CUDA_VERSION)
        CUDA_VISIBLE_DEVICES         List of NVIDIA device indices or UUIDs (i.e. 0,GPU-DEADBEEFDEADBEEF)
        GITCONFIG                    /path/to/.gitconfig (Default: $GITCONFIG_PATH)
        INSTALL_JUPYTER              Install the Jupyter notebook server
                                         [ ${OPTS["INSTALL_JUPYTER"]} ]
        INSTALL_TOOLS                Install debugging and profiling tools (i.e. NSIGHT or ROCm Systems)
                                         [ ${OPTS["INSTALL_TOOLS"]} ]
        INSTALL_LLVM                 Setup the container to build LLVM from source
                                         [ ${OPTS["INSTALL_LLVM"]} ]
        INSTALL_HELION               Install or setup the container for building Helion
                                         [ ${OPTS["INSTALL_HELION"]} ]
        INSTALL_TORCH                Install or setup the container for building PyTorch
                                         [ ${OPTS["INSTALL_TORCH"]} ]
        INSTALL_TRITON               Install or setup the container for building Triton
                                         [ ${OPTS["INSTALL_TRITON"]} ]
        INSTALL_VLLM                 Install or setup the container for building vLLM
                                         [ ${OPTS["INSTALL_VLLM"]} ]
        PIP_HELION_VERSION           Helion wheel version
        PIP_TORCH_INDEX_URL          http://<url> (Default: $PIP_TORCH_INDEX_URL)
        PIP_TORCH_VERSION            Torch wheel version
        PIP_TRITON_VERSION           Triton wheel version
        PIP_VLLM_COMMIT              vLLM git commit hash for wheel install ($VLLM_INDEX_URL_BASE/<commit>)
        PIP_VLLM_EXTRA_INDEX_URL     http://<url> [Not used with PIP_VLLM_COMMIT] (Default: $VLLM_INDEX_URL_BASE)
        PIP_VLLM_VERSION             vLLM wheel version
        ROCM_VERSION                 ROCm version (Default: $ROCM_VERSION)
        ROCR_VISIBLE_DEVICES         List of AMD device indices or UUIDs (i.e. 0,GPU-DEADBEEFDEADBEEF)
        USE_CCACHE                   Enable ccache [ 0 | 1 ] (Default: $USE_CCACHE)
        UV_TORCH_BACKEND             Framwork version: [ cu${CUDA_VERSION//-/} | rocm${ROCM_VERSION%.*} | cpu ]
    -p [ DEFAULT | PORT ]        Expose the specified port for the Jupyter notebook server (Default: $DEFAULT_PORT)
    -r                           Remove the container on exit
    -s SOURCE=PATH               Local source directories to mount as volumes
        LLVM                         /path/to/llvm/source
        HELION                       /path/to/helion/source
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

set_env_var() {
	local key=$1
	local value=$2

	if [[ ! "${CTR_ENV_OPTS[*]}" =~ $key ]]; then
		if [[ "${!OPTS[*]}" =~ $key ]]; then
			if [[ ! "${OPTS[$key]}" =~ $value ]]; then
				echo "Bad option, $value, for $key, can only be ${OPTS[$key]}"
				exit 1
			fi
		fi

		CTR_ENV_OPTS+=("-e $key=$value")
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
	for vol in "${!VOL_DIRS[@]}"; do
		vol_path=${vol}_PATH
		if [ -n "${!vol_path:-}" ]; then
			if [ -d "${!vol_path}" ]; then
				CTR_VOLUME_OPTS+=("-v ${!vol_path}:/workspace/${VOL_DIRS[$vol]}${selinux_flag:-}")
			else
				echo "Specified $vol path, $vol_path, does not exist."
				exit 1
			fi
		fi
	done

	# User management for non-Mac OS's
	if [ "$(uname -s)" != "Darwin" ] && ! getent passwd "$USER" >/dev/null && [ -n "${USERNAME:-}" ]; then
		CTR_VOLUME_OPTS+=("-v /etc/passwd:/etc/passwd:ro -v /etc/group:/etc/group:ro")
	fi

	# Gitconfig
	if [ -f "${GITCONFIG_PATH:-}" ]; then
		CTR_VOLUME_OPTS+=("-v ${GITCONFIG_PATH}:/etc/gitconfig${selinux_flag:-}")
	fi
}

set_device_opts() {
	case $TARGET_DEVICE in
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

		set_env_var ROCM_VERSION "$ROCM_VERSION"
		set_env_var ROCR_VISIBLE_DEVICES "$ROCR_VISIBLE_DEVICES"
		IMAGE_TAG=${ROCM_VERSION}-${DEFAULT_IMAGE_TAG}
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

			if [ -n "${DISPLAY:-}" ] && [ -n "${WAYLAND_DISPLAY:-}" ]; then
				set_env_var DISPLAY "$DISPLAY"
				set_env_var WAYLAND_DISPLAY "$WAYLAND_DISPLAY"
				set_env_var XDG_RUNTIME_DIR /tmp

				CTR_VOLUME_OPTS+=(
					"-v ${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}:/tmp/${WAYLAND_DISPLAY}:ro"
				)
			else
				echo "WARNING: No DISPLAY or WAYLAND_DISPLAY configured"
			fi
		fi

		set_env_var CUDA_VERSION "$CUDA_VERSION"
		set_env_var CUDA_VISIBLE_DEVICES "$CUDA_VISIBLE_DEVICES"
		IMAGE_TAG=${CUDA_VERSION}-${DEFAULT_IMAGE_TAG}
		;;
	esac
}

set_user_args() {
	if [ -z "${USERNAME:-}" ] && [ "$(whoami)" != "root" ]; then
		USERNAME=$(whoami)
	fi

	if [ -n "${USERNAME:-}" ] && [ "${USERNAME:-}" != "root" ]; then
		set_env_var USER "$USERNAME"
		set_env_var USER_UID "$(id -u "$USER")"
		set_env_var USER_GID "$(id -g "$USER")"
	elif [ "$(basename "$CTR_CMD")" = "docker" ]; then
		CTR_ARGS=(
			"--user $(id -u):$(id -g)"
		)
	elif [ "$(basename "$CTR_CMD")" = "podman" ]; then
		CTR_ARGS=(
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
		MAX_JOBS=$OPTARG
		;;
	k)
		TARGET_STACK=$OPTARG
		;;
	o)
		SUBOPT=${OPTARG/=*/}
		case "${SUBOPT^^}" in
		CUDA_VERSION)
			CUDA_VERSION="${OPTARG/*=/}"
			;;
		CUDA_VISIBLE_DEVICES)
			CUDA_VISIBLE_DEVICES="${OPTARG/*=/}"
			;;
		GITCONFIG)
			GITCONFIG_PATH="${OPTARG/*=/}"
			;;
		INSTALL_JUPYTER)
			INSTALL_JUPYTER="${OPTARG/*=/}"
			;;
		INSTALL_TOOLS)
			set_env_var INSTALL_TOOLS "${OPTARG/*=/}"
			;;
		INSTALL_LLVM)
			set_env_var INSTALL_LLVM "${OPTARG/*=/}"
			;;
		INSTALL_HELION)
			set_env_var INSTALL_HELION "${OPTARG/*=/}"
			;;
		INSTALL_TORCH)
			set_env_var INSTALL_TORCH "${OPTARG/*=/}"
			;;
		INSTALL_TRITON)
			set_env_var INSTALL_TRITON "${OPTARG/*=/}"
			;;
		INSTALL_VLLM)
			set_env_var INSTALL_VLLM "${OPTARG/*=/}"
			;;
		PIP_HELION_VERSION)
			set_env_var PIP_HELION_VERSION "${OPTARG/*=/}"
			;;
		PIP_TORCH_INDEX_URL)
			set_env_var PIP_TORCH_INDEX_URL "${OPTARG/*=/}"
			;;
		PIP_TORCH_VERSION)
			set_env_var PIP_TORCH_VERSION "${OPTARG/*=/}"
			;;
		PIP_TRITON_VERSION)
			set_env_var PIP_TRITON_VERSION "${OPTARG/*=/}"
			;;
		PIP_VLLM_COMMIT)
			set_env_var PIP_VLLM_COMMIT "${OPTARG/*=/}"
			;;
		PIP_VLLM_EXTRA_INDEX_URL)
			set_env_var PIP_VLLM_EXTRA_INDEX_URL "${OPTARG/*=/}"
			;;
		PIP_VLLM_VERSION)
			set_env_var PIP_VLLM_VERSION "${OPTARG/*=/}"
			;;
		ROCM_VERSION)
			ROCM_VERSION="${OPTARG/*=/}"
			;;
		ROCR_VISIBLE_DEVICES)
			ROCR_VISIBLE_DEVICES="${OPTARG/*=/}"
			;;
		USE_CCACHE)
			set_env_var USE_CCACHE "${OPTARG/*=/}"
			;;
		UV_TORCH_BACKEND)
			set_env_var UV_TORCH_BACKEND "${OPTARG/*=/}"
			;;
		*)
			echo "Unknown option ${OPTARG}."
			exit 1
			;;
		esac
		;;
	p)
		INSTALL_JUPYTER=true
		if [ "${OPTARG^^}" = "AUTO" ]; then
			JUPYTER_NOTEBOOK_PORT=$DEFAULT_PORT
		else
			JUPYTER_NOTEBOOK_PORT=$OPTARG
		fi
		;;
	r)
		DELETE_ON_EXIT=true
		;;
	s)
		SUBOPT=${OPTARG/=*/}
		case "${SUBOPT^^}" in
		LLVM)
			LLVM_PATH="${OPTARG/*=/}"
			set_env_var "INSTALL_LLVM" source
			;;
		HELION)
			HELION_PATH="${OPTARG/*=/}"
			set_env_var "INSTALL_HELION" source
			;;
		TORCH)
			TORCH_PATH="${OPTARG/*=/}"
			set_env_var "INSTALL_TORCH" source
			;;
		TRITON)
			TRITON_PATH="${OPTARG/*=/}"
			set_env_var "INSTALL_TRITON" source
			;;
		VLLM)
			VLLM_PATH="${OPTARG/*=/}"
			set_env_var "INSTALL_VLLM" source
			;;
		USER)
			USER_PATH="${OPTARG/*=/}"
			;;
		*)
			echo "Unknown source path $OPTARG"
			exit 1
			;;
		esac
		;;
	t)
		IMAGE_TAG=$OPTARG
		;;
	u)
		USERNAME=$OPTARG
		;;
	h)
		usage
		exit 0
		;;
	v)
		set -x
		;;
	*)
		echo "Unknown option $opt."
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
	CTR_PORT_OPT="-p ${JUPYTER_NOTEBOOK_PORT:-$DEFAULT_PORT}:${JUPYTER_NOTEBOOK_PORT:-$DEFAULT_PORT}"
	set_env_var INSTALL_JUPYTER "$INSTALL_JUPYTER"
	set_env_var NOTEBOOK_PORT "${JUPYTER_NOTEBOOK_PORT:-$DEFAULT_PORT}"
fi

# Environment Arguments
set_env_var MAX_JOBS "$MAX_JOBS"

# User args
set_user_args

# Set stack options
if [ -n "${TARGET_STACK:-}" ]; then
	case $TARGET_STACK in
	helion)
		set_env_var INSTALL_HELION "source"
		set_env_var INSTALL_TORCH "release"
		;;
	torch)
		set_env_var INSTALL_TORCH "source"
		;;
	triton)
		set_env_var INSTALL_TORCH "release"
		set_env_var INSTALL_TRITON "source"
		;;
	vllm)
		set_env_var INSTALL_VLLM "source"
		;;
	*)
		echo "Unknown stack, $TARGET_STACK"
		exit 1
		;;
	esac
fi

CTR_ARGS+=(
	"${CTR_ENV_OPTS[@]:-}"
	"${CTR_DEVICE_OPTS[@]:-}"
	"${CTR_PORT_OPT:-}"
	"${CTR_SECURITY_OPTS[@]:-}"
	"${CTR_VOLUME_OPTS[@]:-}"
)

if [ -n "${REMOTE_CONNECTION:-}" ]; then
	CTR_CONNECTION="-r -c $REMOTE_CONNECTION"
fi

if [ "${DELETE_ON_EXIT:-}" = "true" ]; then
	CTR_ARGS+=("--rm")
fi

IMAGE=${IMAGE:-${DEFAULT_IMAGE_REPO}/${TARGET_DEVICE}:${IMAGE_TAG:-${DEFAULT_IMAGE_TAG}}}

printf "Running container image: %s with %s\n" "$IMAGE" "$CTR_CMD"
printf "%s %s run -ti %s %s bash\n" "$CTR_CMD" "${CTR_CONNECTION:-}" \
	"${CTR_ARGS[*]}" "$IMAGE"
$CTR_CMD ${CTR_CONNECTION:-} run -ti ${CTR_ARGS[@]} "${IMAGE}" bash
