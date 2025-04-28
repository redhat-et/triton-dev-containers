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
ARG LLVM_TAG

FROM registry.access.redhat.com/ubi9/ubi:latest AS llvm-build
ARG CUSTOM_LLVM
ARG LLVM_TAG

USER 0
# Conditionally execute the build if CUSTOM_LLVM is true or LLVM_TAG is set
RUN if [ "$CUSTOM_LLVM" = "true" ] || [ -n "$LLVM_TAG" ]; then \
        dnf update -y && \
        dnf -y install clang rpm-build git ninja-build cmake lld && \
        git clone https://github.com/llvm/llvm-project && \
        cd llvm-project && \
        COMMIT="${LLVM_TAG:-$(curl -s https://raw.githubusercontent.com/triton-lang/triton/refs/heads/main/cmake/llvm-hash.txt)}" &&\
        git checkout $COMMIT && \
        mkdir build && \
        cd build && \
        cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_ASSERTIONS=ON ../llvm -DLLVM_ENABLE_PROJECTS="mlir;llvm" -DLLVM_TARGETS_TO_BUILD="host;NVPTX;AMDGPU" && \
        ninja; \
    else \
        echo "Skipping LLVM build because neither CUSTOM_LLVM is true nor LLVM_TAG is set"; \
        mkdir llvm-project; \
    fi

FROM registry.access.redhat.com/ubi9/python-312 AS final
ARG USERNAME=1001
ARG USER_UID=1000
ARG USER_GID=$USER_UID
ARG CUSTOM_LLVM
ARG LLVM_TAG
ARG CUDA_REPO=https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo
ARG CUDA_VERSION=12-8

USER 0
COPY user.sh user.sh
# Create the user
RUN ./user.sh -u $USERNAME -g $USER_GID -i $USER_UID
RUN dnf update -y && \
    dnf -y config-manager --add-repo ${CUDA_REPO} && \
    dnf -y install clang cmake lld ninja-build && \
    dnf install -y --nodocs --setopt=install_weak_deps=False \
    cublasmp cuda-cupti-${CUDA_VERSION} cuda-gdb-${CUDA_VERSION} \
    cuda-nsight-${CUDA_VERSION} cuda-nsight-compute-${CUDA_VERSION} \
    cuda-nsight-systems-${CUDA_VERSION}
# Set the user
USER $USERNAME

RUN python -m venv /opt && \
    echo "unset BASH_ENV PROMPT_COMMAND ENV" >> /opt/bin/activate && \
    chmod -R 777 /opt

RUN echo 'source /opt/bin/activate' >> "${HOME}"/.bashrc

ENV BASH_ENV=/opt/bin/activate \
    ENV=/opt/bin/activate \
    PIP_PREFIX=/opt \
    PYTHONPATH=/opt/lib/python$PYTHON_VERSION/site-packages \
    PYTHON_VERSION=3.12 \
    PATH=$HOME/.local/bin/:/opt/bin:$PATH \
    PYTHONUNBUFFERED=1

COPY --from=llvm-build /llvm-project/ /llvm-project/

# Install dependencies
RUN source /opt/bin/activate && \
    pip install --upgrade pip && \
    pip install --upgrade setuptools && \
    pip install ninja cmake wheel pybind11 pre-commit pytest
RUN if [[ "$INSTALL_CUDNN" == "true" ]]; then \
    source /opt/bin/activate && pip install nvidia-cudnn-cu12; \
fi

RUN echo "export MAX_JOBS=$(nproc --all)" >> "${HOME}"/.bashrc
# Conditionally set the env vars based on CUSTOM_LLVM
RUN if [[ "$CUSTOM_LLVM" == "true" || -n "$LLVM_TAG" ]]; then \
    echo "export LLVM_BUILD_DIR=/llvm-project/build" >> "${HOME}/.bashrc" && \
    echo "export LLVM_INCLUDE_DIRS=/llvm-project/build/include" >> "${HOME}/.bashrc" && \
    echo "export LLVM_LIBRARY_DIR=/llvm-project/build/lib" >> "${HOME}/.bashrc" && \
    echo "export LLVM_SYSPATH=/llvm-project/build" >> "${HOME}/.bashrc"; \
fi
