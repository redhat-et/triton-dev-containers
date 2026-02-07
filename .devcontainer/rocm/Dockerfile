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

ARG PYTHON_VERSION=3.12
ARG ROCM_VERSION=6.3.4
ARG ROCR_VISIBLE_DEVICES=0

ARG AMDGPU_INSTALL_URL=https://repo.radeon.com/amdgpu-install/${ROCM_VERSION}/rhel

# Install the AMD ROCm Repo and GPG key
RUN source /etc/os-release && \
    if [ "$VERSION_ID" = "10.0" ]; then RHEL_VERSION=${VERSION_ID%.*}; else RHEL_VERSION=${VERSION_ID}; fi; \
    AMDGPU_INSTALL_RPM=$(curl -s ${AMDGPU_INSTALL_URL}/${RHEL_VERSION}/ | grep href | sed -e 's/.*href="//' -e 's/".*//' |grep "amdgpu-install-${ROCM_VERSION%.*}.*${PLATFORM_ID#*:}.noarch.rpm") && \
    dnf -y install ${AMDGPU_INSTALL_URL}/${RHEL_VERSION}/${AMDGPU_INSTALL_RPM}

RUN dnf install -y clang clang-libs git lld llvm \
    python${PYTHON_VERSION}-devel python${PYTHON_VERSION}-pip && \
    dnf install -y --nodocs --setopt=install_weak_deps=False \
    amd-smi-lib \
    miopen-hip \
    rocm-core \
    rocm-hip-libraries \
    rocminfo && \
    dnf clean all && rm -rf /var/cache/yum

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
    ${HOME}/.local/bin/uv venv --python $PYTHON_VERSION --seed /opt/venv && \
    echo "unset BASH_ENV PROMPT_COMMAND ENV" >> /opt/venv/bin/activate && \
    chmod -R 777 /opt

RUN tee -a "${HOME}"/.bashrc <<EOF
export MAX_JOBS=$(nproc --all)
source /opt/venv/bin/activate
EOF

ENV BASH_ENV=/opt/venv/bin/activate \
    ENV=/opt/venv/bin/activate \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    LD_LIBRARY_PATH=/usr/lib64:/usr/lib:/opt/rocm/lib:/opt/rocm/llvm/lib \
    PATH=${HOME}/.local/bin/:/opt/venv/bin:/opt/rocm/bin:/opt/rocm/llvm/bin:$PATH \
    PIP_PREFIX=/opt/venv \
    PYTHONPATH=/opt/venv/lib/python${PYTHON_VERSION}/site-packages \
    PYTHON_VERSION=$PYTHON_VERSION \
    PYTHONUNBUFFERED=1 \
    ROCM_PATH=/opt/rocm \
    ROCM_VERSION=$ROCM_VERSION \
    ROCR_VISIBLE_DEVICES=$ROCR_VISIBLE_DEVICES \
    UV_TOOL_BIN_DIR=/opt/venv/bin \
    VIRTUAL_ENV=/opt/venv \
    WORKSPACE=$WORKSPACE

# Install dependencies
RUN source /opt/venv/bin/activate && \
    ${HOME}/.local/bin/uv pip install --upgrade pip setuptools && \
    ${HOME}/.local/bin/uv pip install ninja cmake wheel pybind11 tabulate \
    scipy ninja cmake numpy pyyaml ctypeslib2 matplotlib pandas pytest && \
    ${HOME}/.local/bin/uv pip install --no-cache-dir torch \
    --index-url https://download.pytorch.org/whl/rocm$(echo $ROCM_VERSION | sed -e 's/\([0-9]\.[0-9]\).*/\1/') && \
    ${HOME}/.local/bin/uv pip install pre-commit

WORKDIR $WORKSPACE
