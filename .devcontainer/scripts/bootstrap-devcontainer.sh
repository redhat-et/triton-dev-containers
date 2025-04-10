#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
# Copyright (C) 2024 Red Hat

set -euo pipefail

VALID_VARIANTS=("triton" "triton-cpu" "triton-amd" "triton-profiling")
VARIANT="${1:-}"

is_valid_variant() {
  [[ " ${VALID_VARIANTS[*]} " =~ ${1} ]]
}

if [[ -n "$VARIANT" ]]; then
  if ! is_valid_variant "$VARIANT"; then
    echo "Invalid variant: $VARIANT"
    echo "  Valid variants: ${VALID_VARIANTS[*]}"
    exit 1
  fi
  VARIANTS_TO_PROCESS=("$VARIANT")
else
  VARIANTS_TO_PROCESS=("${VALID_VARIANTS[@]}")
fi

echo "Bootstrapping devcontainer for variant(s): ${VARIANT:-ALL}"

# Clone shallowly
echo "Cloning devcontainer repository..."
git clone -n --depth=1 --filter=tree:0 https://github.com/redhat-et/triton-dev-containers.git .devcontainer
TARGET_DIR=".devcontainer"
(
  cd "$TARGET_DIR" || exit 1

  echo "Configuring sparse-checkout..."
  if [[ -n "$VARIANT" ]]; then
    git sparse-checkout set --no-cone \
      .devcontainer/Makefile \
      .devcontainer/base \
      .devcontainer/scripts \
      .devcontainer/"$VARIANT"
  else
    # Full checkout of everything in .devcontainer
    git sparse-checkout set --no-cone .devcontainer
  fi

  git checkout

  echo "Moving files into place..."
  mv .devcontainer/Makefile ./Makefile
  mv .devcontainer/base ./base
  mv .devcontainer/scripts ./scripts
  for v in "${VARIANTS_TO_PROCESS[@]}"; do
    mv ".devcontainer/$v" "./$v"
  done

  if [[ -n "$VARIANT" ]]; then
    echo "Generating devcontainer.json for $VARIANT..."
    make generate v="$VARIANT"
    echo "Removing build-time files..."
  else
    echo "Generating devcontainer.json for variants: ${VARIANTS_TO_PROCESS[*]}"
    make generate
  fi

  echo "Cleaning up temporary clone..."
  rm -rf base scripts Makefile
  rm -rf .git
  rm -rf .devcontainer
)

echo "Adding .devcontainer to .gitignore..."
grep -qxF '.devcontainer' .gitignore || echo '.devcontainer' >> .gitignore

echo "Done. You can now open the folder in VSCode and use the Dev Container."
