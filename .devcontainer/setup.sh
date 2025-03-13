#! /bin/bash -e
# SPDX-License-Identifier: BSD-3-Clause
# Copyright (C) 2024-2025 Red Hat, Inc.

set -euo pipefail

SCRIPT_DIR=$(dirname "$(realpath "$0")")

declare -a files=(
    "$SCRIPT_DIR/triton/devcontainer.json"
    "$SCRIPT_DIR/triton-amd/devcontainer.json"
    "$SCRIPT_DIR/triton-cpu/devcontainer.json"
)

UID_VAL=$(id -u)
GID_VAL=$(id -g)
USERNAME=$(id -un)

is_podman() {
    command -v podman &> /dev/null && podman info &> /dev/null
}

is_nvidia_cdi_available() {
    if command -v nvidia-ctk &> /dev/null && nvidia-ctk cdi list | grep -q "nvidia.com/gpu=all"; then
        return 0
    fi
    return 1
}

for var in "${files[@]}"; do
    if [ -f "$var" ]; then
        if is_podman; then
            sed -i "s/\"--userns=keep-id:uid=[0-9]\+,gid=[0-9]\+\"/\"--userns=keep-id:uid=$UID_VAL,gid=$GID_VAL\"/" "$var"
        fi

        if is_nvidia_cdi_available; then
            sed -i "/--runtime=nvidia/d" "$var"
            sed -i "s|\"--gpus all\"|\"--device\",\n    \"nvidia.com/gpu=all\"|" "$var"
            sed -i "/\"gpu\": \"optional\"/d" "$var"
        fi

        sed -i "s/\"remoteUser\": \"\${localEnv:USER}\"/\"remoteUser\": \"$USERNAME\"/g" "$var"
        sed -i "s/\"containerUser\": \"\${localEnv:USER}\"/\"containerUser\": \"$USERNAME\"/g" "$var"
    fi
done
