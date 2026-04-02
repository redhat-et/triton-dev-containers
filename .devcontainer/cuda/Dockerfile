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
ARG UBI_IMAGE=ubi
ARG UBI_VERSION=9

FROM registry.access.redhat.com/ubi${UBI_VERSION}/${UBI_IMAGE}

ARG CUDA_VERSION=12.9.1
ARG CUDA_VISIBLE_DEVICES=0
ARG PYTHON_VERSION=3.12

RUN dnf update -y && \
    dnf -y install clang cmake git lld ninja-build \
    python${PYTHON_VERSION}-devel python${PYTHON_VERSION}-pip && \
    dnf clean all && rm -rf /var/cache/dnf

ARG USERNAME=triton
ARG USER_UID=1000
ARG USER_GID=$USER_UID
ARG WORKSPACE=/workspace
WORKDIR $WORKSPACE

# Create the user
COPY create_user.sh create_user.sh
RUN ./create_user.sh -u $USERNAME -g $USER_GID -i $USER_UID

USER $USERNAME

RUN python${PYTHON_VERSION} -m pip install uv && \
    ${HOME}/.local/bin/uv venv --python ${PYTHON_VERSION} --seed /opt/venv && \
    echo "unset BASH_ENV PROMPT_COMMAND ENV" >> /opt/venv/bin/activate && \
    chmod -R 777 /opt/venv

RUN tee -a "${HOME}"/.bashrc <<EOF
export MAX_JOBS=$(nproc --all)
source /opt/venv/bin/activate
EOF

ENV BASH_ENV=/opt/venv/bin/activate \
    CUDA_VERSION=$CUDA_VERSION \
    CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES \
    ENV=/opt/venv/bin/activate \
    PATH=${HOME}/.local/bin/:/opt/venv/bin:$PATH \
    PIP_PREFIX=/opt/venv \
    PYTHON_VERSION=3.12 \
    PYTHONPATH=/opt/venv/lib/python$PYTHON_VERSION/site-packages \
    PYTHONUNBUFFERED=1 \
    UV_TOOL_BIN_DIR=/opt/venv/bin \
    VIRTUAL_ENV=/opt/venv \
    WORKSPACE=$WORKSPACE

# Install dependencies
RUN source /opt/venv/bin/activate && \
    ${HOME}/.local/bin/uv pip install --upgrade pip setuptools && \
    ${HOME}/.local/bin/uv pip install ninja cmake wheel pybind11 pre-commit pytest

WORKDIR $WORKSPACE
