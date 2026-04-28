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

ARG CENTOS_VERSION=10
FROM quay.io/centos/centos:stream${CENTOS_VERSION}-minimal AS gosu

USER 0

ARG GOSU_VERSION=1.19
ENV GOSU_VERSION=${GOSU_VERSION}
RUN microdnf update -y && \
    microdnf install -y wget && \
    microdnf clean all
RUN set -eux; \
    rpmArch="$(rpm --query --queryformat='%{ARCH}' rpm)"; \
    case "$rpmArch" in \
    aarch64) dpkgArch='arm64' ;; \
    armv[67]*) dpkgArch='armhf' ;; \
    i[3456]86) dpkgArch='i386' ;; \
    ppc64le) dpkgArch='ppc64el' ;; \
    riscv64 | s390x) dpkgArch="$rpmArch" ;; \
    x86_64) dpkgArch='amd64' ;; \
    *) echo >&2 "error: unknown/unsupported architecture '$rpmArch'"; exit 1 ;; \
    esac; \
    wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-$dpkgArch"; \
    chmod +x /usr/local/bin/gosu && \
    rm -rf /tmp/*

FROM quay.io/centos/centos:stream${CENTOS_VERSION} AS base

ARG CENTOS_VERSION
ARG PYTHON_VERSION=3.12
ARG WORKSPACE=/workspace

USER 0

COPY --from=gosu /usr/local/bin/gosu /usr/local/bin/gosu

# Install the EPEL repo and enable CRB
ARG EPEL_REPO=https://dl.fedoraproject.org/pub/epel/epel-release-latest-${CENTOS_VERSION}.noarch.rpm
RUN dnf -y install 'dnf-command(config-manager)' && \
	dnf -y config-manager --set-enabled crb && \
	dnf -y install ${EPEL_REPO} && \
    /usr/bin/crb enable && \
    dnf -y update

# Install base software
RUN dnf -y update && \
    dnf -y install clang cmake git glibc-langpack-en libxml2-devel \
    lld llvm llvm-libs libomp libomp-devel ninja-build openblas openblas-devel \
    python${PYTHON_VERSION}-devel python${PYTHON_VERSION}-pip vim zlib-devel && \
    dnf clean all

# Create the /workspace directory and set permissions
WORKDIR $WORKSPACE
RUN python${PYTHON_VERSION} -m pip install uv && \
    uv venv --python ${PYTHON_VERSION} --seed $WORKSPACE && \
    echo "unset BASH_ENV PROMPT_COMMAND ENV" >> ${WORKSPACE}/bin/activate && \
    chmod -R 777 $WORKSPACE

ENV BASH_ENV=${WORKSPACE}/bin/activate \
    ENV=${WORKSPACE}/bin/activate \
    LANG=en_US.UTF-8 \
    LC_ALL=C.UTF-8 \
    PATH=${WORKSPACE}/bin:$PATH \
    PIP_PREFIX=$WORKSPACE \
    PROMPT_COMMAND=". ${WORKSPACE}/bin/activate" \
    PYTHON_VERSION=$PYTHON_VERSION \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=${WORKSPACE}/lib/python${PYTHON_VERSION}/site-packages \
    TRITON_HOME=$WORKSPACE \
    TRITON_CACHE_DIR=${WORKSPACE}/.triton/cache \
    CENTOS_VERSION=$CENTOS_VERSION \
    UV_HTTP_TIMEOUT=60 \
    WORKSPACE=$WORKSPACE \
    XDG_CACHE_HOME=$WORKSPACE

COPY scripts/devcreate_user.sh ${WORKSPACE}/bin/devcreate_user
COPY scripts/devinstall_llvm.sh ${WORKSPACE}/bin/devinstall_llvm
COPY scripts/devinstall_torch.sh ${WORKSPACE}/bin/devinstall_torch
COPY scripts/devinstall_helion.sh ${WORKSPACE}/bin/devinstall_helion
COPY scripts/devinstall_software.sh ${WORKSPACE}/bin/devinstall_software
COPY scripts/devinstall_triton.sh ${WORKSPACE}/bin/devinstall_triton
COPY scripts/devinstall_vllm.sh ${WORKSPACE}/bin/devinstall_vllm
COPY scripts/devsetup.sh ${WORKSPACE}/bin/devsetup
COPY scripts/ldpretend.sh ${WORKSPACE}/bin/ldpretend

COPY hack/triton-gpu-check.py triton-gpu-check.py
