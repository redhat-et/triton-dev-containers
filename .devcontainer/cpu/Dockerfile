ARG UBI_IMAGE=ubi
ARG UBI_VERSION=9

FROM registry.access.redhat.com/ubi${UBI_VERSION}/${UBI_IMAGE}

ARG PYTHON_VERSION=3.12

RUN dnf -y update && \
    dnf -y install git python${PYTHON_VERSION}-devel \
    python${PYTHON_VERSION}-pip && \
    dnf clean all && rm -rf /var/cache/dnf

ARG USERNAME=triton
ARG USER_UID=1000
ARG USER_GID=$USER_UID
ARG WORKSPACE=/workspace
WORKDIR /workspace

# Create the user
COPY create_user.sh create_user.sh
RUN ./create_user.sh -u $USERNAME -g $USER_GID -i $USER_UID

USER $USERNAME

RUN python${PYTHON_VERSION} -m pip install uv && \
    ${HOME}/.local/bin/uv venv --python $PYTHON_VERSION --seed /opt/venv && \
    echo "unset BASH_ENV PROMPT_COMMAND ENV" >> /opt/venv/bin/activate && \
    chmod -R 777 /opt/venv

ENV BASH_ENV=/opt/venv/bin/activate \
    ENV=/opt/venv/bin/activate \
    PIP_PREFIX=/opt/venv/ \
    PATH=${HOME}/.local/bin/:/opt/venv/bin:$PATH \
    PYTHON_VERSION=$PYTHON_VERSION \
    PYTHONPATH=/opt/venv/lib/python${PYTHON_VERSION}/site-packages \
    PYTHONUNBUFFERED=1 \
    TRITON_CPU_BACKEND=1 \
    UV_TOOL_BIN_DIR=/opt/venv/bin \
    VIRTUAL_ENV=/opt/venv \
    WORKSPACE=$WORKSPACE

RUN tee -a "${HOME}"/.bashrc <<EOF
export MAX_JOBS=$(nproc --all)
source /opt/venv/bin/activate
EOF

RUN source /opt/venv/bin/activate && \
    ${HOME}/.local/bin/uv pip install --upgrade pip setuptools && \
    ${HOME}/.local/bin/uv pip install ninja cmake wheel pybind11 pre-commit pytest


WORKDIR $WORKSPACE
