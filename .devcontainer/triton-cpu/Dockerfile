FROM registry.access.redhat.com/ubi9/python-312

ARG USERNAME=1001
ARG USER_UID=1000
ARG USER_GID=$USER_UID

USER 0
COPY user.sh user.sh
RUN ./user.sh -u $USERNAME -g $USER_GID -i $USER_UID
USER $USERNAME

RUN python -m venv /opt && \
    echo "unset BASH_ENV PROMPT_COMMAND ENV" >> /opt/bin/activate && \
    chmod -R 777 /opt

ENV BASH_ENV=/opt/bin/activate \
    ENV=/opt/bin/activate \
    PIP_PREFIX=/opt \
    PYTHONPATH=/opt/lib/python$PYTHON_VERSION/site-packages \
    PYTHON_VERSION=3.12 \
    PATH=$HOME/.local/bin/:/opt/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    TRITON_CPU_BACKEND=1

RUN echo 'source /opt/bin/activate' >> "${HOME}"/.bashrc

RUN source /opt/bin/activate && \
    pip install --upgrade pip setuptools && \
    pip install ninja cmake wheel pybind11 pre-commit pytest

RUN echo "export MAX_JOBS=$(nproc --all)" >> "${HOME}"/.bashrc
