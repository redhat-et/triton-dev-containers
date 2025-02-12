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

# Get the current user's UID and GID
UID_VAL=$(id -u)
GID_VAL=$(id -g)

# Update devcontainer.json with the correct UID and GID
for var in "${files[@]}"; do
    if [ -f "$var" ]; then
        sed -i "s/\"--userns=keep-id:uid=[0-9]\+,gid=[0-9]\+\"/\"--userns=keep-id:uid=$UID_VAL,gid=$GID_VAL\"/" "$var"
    fi
done
