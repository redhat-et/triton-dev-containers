#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
# Copyright (C) 2024 Red Hat

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$BASE_DIR/base/devcontainer.template.json"
UID_VAL="$(id -u)"
GID_VAL="$(id -g)"
USERNAME="$(id -un)"
HIP_DEVICES="${HIP_VISIBLE_DEVICES:-0}"

is_podman() {
  command -v podman &> /dev/null && podman info &> /dev/null
}

is_nvidia_cdi_available() {
  command -v nvidia-ctk &> /dev/null && nvidia-ctk cdi list | grep -q "nvidia.com/gpu=all"
}

# Accept variant as first argument, default to all
if [[ $# -eq 1 ]]; then
  variants=("$1")
else
  variants=("triton" "triton-cpu" "triton-amd")
fi

# Define mount consistency options based on runtime
if is_podman; then
  mount_consistency="consistency=cached,Z"
  userns_arg="--userns=keep-id:uid=$UID_VAL,gid=$GID_VAL"
else
  mount_consistency="consistency=cached"
  userns_arg=""
fi

for variant in "${variants[@]}"; do
  overlay="$BASE_DIR/$variant/overlay.json"
  output="$BASE_DIR/$variant/devcontainer.json"

  if [[ ! -f "$overlay" ]]; then
    echo "Skipping $variant — overlay file not found: $overlay"
    continue
  fi

  echo "Generating devcontainer for: $variant"
  echo " - Overlay: $overlay"
  echo " - Output:  $output"

  jq -s --arg uid "$UID_VAL" \
        --arg gid "$GID_VAL" \
        --arg username "$USERNAME" \
        --arg hip "$HIP_DEVICES" \
        --arg mount_opts "$mount_consistency" \
        --arg userns "$userns_arg" \
        '.[0] * .[1]
          | .remoteUser = $username
          | .containerUser = $username
          | .containerEnv.USERNAME = $username
          | .containerEnv.USER_UID = $uid
          | .containerEnv.USER_GID = $gid
          | .build.args.USERNAME = $username
          | .build.args.USER_UID = $uid
          | .build.args.USER_GID = $gid
          | .workspaceMount |= sub("consistency=cached(,Z)?"; $mount_opts)
          | (if has("containerEnv") and (.containerEnv | has("HIP_VISIBLE_DEVICES")) then
               .containerEnv.HIP_VISIBLE_DEVICES = $hip
             else . end)
          | (if $userns != "" then
               .runArgs = (.runArgs // [] | map(select(test("^--userns=") | not)) + [$userns])
             else
               .runArgs = (.runArgs // [] | map(select(test("^--userns=") | not)))
             end)' \
      "$TEMPLATE" "$overlay" > "$output"

  if is_nvidia_cdi_available; then
      sed -i "/--runtime=nvidia/d" "$output"
      sed -i "s|\"--gpus all\"|\"--device\",\n    \"nvidia.com/gpu=all\"|" "$output"
      sed -i "/\"gpu\": \"optional\"/d" "$output"
  fi

  # Always copy shared scripts to ensure isolation
  for f in user.sh postStartCommand.sh; do
    cp "$BASE_DIR/base/$f" "$BASE_DIR/$variant/$f"
  done
done
