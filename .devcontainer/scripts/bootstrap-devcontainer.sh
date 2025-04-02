#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
# Copyright (C) 2024 Red Hat

set -euo pipefail

VALID_VARIANTS=("triton" "triton-cpu" "triton-amd")
VARIANT="${1:-}"

is_valid_variant() {
  [[ " ${VALID_VARIANTS[*]} " =~ ${1} ]]
}

if [[ -n "$VARIANT" ]]; then
  if ! is_valid_variant "$VARIANT"; then
    echo " Invalid variant: $VARIANT"
    echo "   Valid variants: ${VALID_VARIANTS[*]}"
    exit 1
  fi
fi

echo "Bootstrapping devcontainer for variant: $VARIANT"

# Clone shallow and filter tree
echo "Cloning devcontainer repository..."
git clone -n --depth=1 --filter=tree:0 https://github.com/redhat-et/triton-dev-containers.git .devcontainer
TARGET_DIR=".devcontainer"
(
  cd "$TARGET_DIR" || exit 1
  echo "Configuring sparse-checkout..."
  git sparse-checkout set --no-cone \
    .devcontainer/Makefile \
    .devcontainer/base \
    .devcontainer/scripts \
    .devcontainer/"$VARIANT"

  git checkout

  echo "Moving files into place..."
  mv .devcontainer/base ./base
  mv .devcontainer/scripts ./scripts
  mv .devcontainer/Makefile ./Makefile
  mv .devcontainer/"$VARIANT" ./"$VARIANT"

  echo "Cleaning up temporary clone..."
  rm -rf .devcontainer .git

  echo "Generating devcontainer.json for $VARIANT..."
  make generate v="$VARIANT"

  echo "Removing build-time files..."
  rm -rf base scripts Makefile
)

echo "Adding .devcontainer to .gitignore..."
grep -qxF '.devcontainer' .gitignore || echo '.devcontainer' >> .gitignore

echo "Done. You can now open the folder in VSCode and use the Dev Container."
