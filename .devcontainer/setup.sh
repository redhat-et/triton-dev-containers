#!/bin/bash -e
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
HIP_DEVICES=${HIP_VISIBLE_DEVICES:-0}

is_podman() {
    command -v podman &> /dev/null && podman info &> /dev/null
}

is_nvidia_cdi_available() {
    command -v nvidia-ctk &> /dev/null && nvidia-ctk cdi list | grep -q "nvidia.com/gpu=all"
}

tmp_file=$(mktemp)

for var in "${files[@]}"; do
    if [ -f "$var" ]; then
        echo "Fixing up $var..."

        read -r -d '' jq_script <<'EOF'
.remoteUser = $user
| .containerUser = $user
| .containerEnv.USERNAME = $user
| .containerEnv.USER_UID = $uid
| .containerEnv.USER_GID = $gid
EOF

        jq_args=(--arg user "$USERNAME" --arg uid "$UID_VAL" --arg gid "$GID_VAL")

        if [[ "$var" == *"triton-amd/devcontainer.json" ]]; then
            jq_script+=" | .containerEnv.HIP_VISIBLE_DEVICES = \$hip"
            jq_args+=(--arg hip "$HIP_DEVICES")
        fi

        jq "${jq_args[@]}" "$jq_script" "$var" > "$tmp_file" && mv "$tmp_file" "$var"

        # Add --security-opt=label=disable if not already present
        if ! grep -q '"--security-opt=label=disable"' "$var"; then
            jq '.runArgs |= (["--security-opt=label=disable"] + .)' "$var" > "$tmp_file" && mv "$tmp_file" "$var"
        fi

        # Podman userns fix
        if is_podman; then
            sed -i "s/\"--userns=keep-id:uid=[0-9]\+,gid=[0-9]\+\"/\"--userns=keep-id:uid=$UID_VAL,gid=$GID_VAL\"/" "$var"
        fi

        # NVIDIA CDI fix
        if [[ "$var" == *"triton/devcontainer.json" ]]; then
            if is_nvidia_cdi_available; then
                sed -i "/--runtime=nvidia/d" "$var"
                sed -i 's|"--gpus all"|"--device",\n    "nvidia.com/gpu=all"|' "$var"
            fi
        fi
    fi
done

echo "Devcontainer files updated successfully."
