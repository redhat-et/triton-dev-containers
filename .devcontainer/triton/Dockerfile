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

FROM registry.access.redhat.com/ubi9/python-312
ARG USERNAME=1001
ARG USER_UID=1000
ARG USER_GID=$USER_UID
ARG INSTALL_CUDNN

USER 0
COPY user.sh user.sh
# Create the user
RUN ./user.sh -u $USERNAME -g $USER_GID -i $USER_UID
RUN dnf update -y && \
    dnf -y install clang cmake lld ninja-build

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

# Install dependencies
RUN source /opt/bin/activate && \
    pip install --upgrade pip && \
    pip install --upgrade setuptools && \
    pip install ninja cmake wheel pybind11 pre-commit pytest
RUN if [[ "$INSTALL_CUDNN" == "true" ]]; then \
    source /opt/bin/activate && pip install nvidia-cudnn-cu12; \
fi

RUN echo "export MAX_JOBS=$(nproc --all)" >> "${HOME}"/.bashrc
