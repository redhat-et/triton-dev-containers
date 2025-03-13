# Copyright (C) 2024-2025 Red Hat, Inc.
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
ARG CUSTOM_LLVM=false
ARG TRITON_CPU_BACKEND=1

FROM registry.access.redhat.com/ubi9/python-312:latest AS llvm-build
ARG CUSTOM_LLVM
ARG TRITON_CPU_BACKEND=1
USER 0
# Conditionally execute the build based on CUSTOM_LLVM
RUN if [ "$CUSTOM_LLVM" = "true" ]; then \
    dnf update -y && \
    dnf -y install clang rpm-build git ninja-build cmake lld && \
    dnf clean all && rm -rf /var/cache/dnf && \
    python3 -m pip install --upgrade pip && \
    python3 -m pip install --upgrade cmake ninja sccache pybind11 && \
    if [ ! -d "/llvm-project" ]; then \
        git clone https://github.com/llvm/llvm-project /llvm-project; \
    else \
        cd /llvm-project && git fetch origin; \
    fi && \
    cd /llvm-project && \
    python3 -m pip install -r mlir/python/requirements.txt && \
    REPO="triton"; \
    PROJECTS="mlir;llvm"; \
    if [ "$TRITON_CPU_BACKEND" = "1" ]; then REPO="triton-cpu" PROJECTS="mlir;llvm;lld"; fi; \
    COMMIT=$(curl -s https://raw.githubusercontent.com/triton-lang/$REPO/refs/heads/main/cmake/llvm-hash.txt) && \
    CURRENT_COMMIT=$(git rev-parse HEAD) && \
    if [ "$CURRENT_COMMIT" != "$COMMIT" ] || [ ! -f "/install/bin/llvm-config" ] || [ ! -d "/install/lib" ]; then \
        echo "LLVM commit mismatch or missing install. Rebuilding..."; \
        git checkout $COMMIT && \
        mkdir -p build && cd build && \
        cmake -G Ninja -DCMAKE_BUILD_TYPE=Release \
            -DLLVM_ENABLE_ASSERTIONS=ON ../llvm \
            -DCMAKE_INSTALL_PREFIX=/install \
            -DLLVM_BUILD_UTILS=ON \
            -DLLVM_BUILD_TOOLS=ON \
            -DMLIR_ENABLE_BINDINGS_PYTHON=ON \
            -DLLVM_INSTALL_UTILS=ON \
            -DLLVM_TARGETS_TO_BUILD="host;NVPTX;AMDGPU" \
            -DLLVM_ENABLE_PROJECTS=$PROJECTS && \
        ninja check-mlir install; \
    else \
        echo "LLVM is already up-to-date. Skipping rebuild."; \
    fi \
    else \
        echo "Skipping LLVM build because CUSTOM_LLVM is not true"; \
        mkdir -p /install; \
    fi

FROM registry.access.redhat.com/ubi9/python-312 AS base

ARG USERNAME=1001
ARG USER_UID=1000
ARG USER_GID=$USER_UID
ARG CUSTOM_LLVM

USER 0
COPY user.sh user.sh
# Create the user
RUN ./user.sh -u $USERNAME -g $USER_GID -i $USER_UID
# Set the user
USER $USERNAME

# Stage for llvm-local-true
FROM base AS llvm-local-true
COPY --from=llvm-build /install /llvm-project/install

# Stage for llvm-local-false
FROM base AS llvm-local-false
ENV TRITON_OFFLINE_BUILD=NO

# Use intermediate stage selection
FROM llvm-local-${CUSTOM_LLVM}
ENV PYTHON_VERSION=3.12 \
    PATH=$HOME/.local/bin/:$PATH \
    PYTHONUNBUFFERED=1 \
    TRITON_CPU_BACKEND=1

# install dependencies
RUN pip install --upgrade pip
RUN pip install --upgrade setuptools
RUN pip install ninja cmake wheel pybind11;
RUN pip install pre-commit
RUN echo "export MAX_JOBS=$(nproc --all)" >> "${HOME}"/.bashrc
# Conditionally set the env vars based on CUSTOM_LLVM
RUN if [ "$CUSTOM_LLVM" = "true" ]; then \
    echo "export LLVM_BUILD_DIR=/llvm-project/install " >> "${HOME}/.bashrc" && \
    echo "export LLVM_INCLUDE_DIRS=/llvm-project/install/include" >> "${HOME}/.bashrc" && \
    echo "export LLVM_LIBRARY_DIR=/llvm-project/install/lib" >> "${HOME}/.bashrc" && \
    echo "export LLVM_SYSPATH=/llvm-project/install" >> "${HOME}/.bashrc"; \
fi
