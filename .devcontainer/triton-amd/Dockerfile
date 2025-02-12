ARG CUSTOM_LLVM=false
ARG ROCM_VERSION=6.2
ARG HIP_VISIBLE_DEVICES=0

FROM registry.access.redhat.com/ubi9/ubi:latest AS llvm-build
ARG CUSTOM_LLVM
USER 0
# Conditionally execute the build based on CUSTOM_LLVM
RUN if [ "$CUSTOM_LLVM" = "true" ]; then \
        dnf update -y && \
        dnf -y install clang rpm-build git ninja-build cmake lld && \
        git clone https://github.com/llvm/llvm-project && \
        cd llvm-project && \
        COMMIT=$(curl -s https://raw.githubusercontent.com/triton-lang/triton/refs/heads/main/cmake/llvm-hash.txt) &&\
        git checkout $COMMIT && \
        mkdir build && \
        cd build && \
        cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_ASSERTIONS=ON ../llvm -DLLVM_ENABLE_PROJECTS="mlir;llvm" -DLLVM_TARGETS_TO_BUILD="host;NVPTX;AMDGPU" && \
        ninja; \
    else \
        echo "Skipping LLVM build because CUSTOM_LLVM is not true"; \
    fi

FROM registry.access.redhat.com/ubi9/python-312 AS base
ARG USERNAME=1001
ARG USER_UID=1000
ARG USER_GID=$USER_UID
ARG CUSTOM_LLVM=false
ARG ROCM_VERSION=6.2
ARG HIP_VISIBLE_DEVICES=0

USER 0
COPY user.sh user.sh
# Create the user
RUN ./user.sh -u $USERNAME -g $USER_GID -i $USER_UID

RUN echo "[ROCm]" > /etc/yum.repos.d/rocm.repo && \
    echo "name=ROCm" >> /etc/yum.repos.d/rocm.repo && \
    echo "baseurl=https://repo.radeon.com/rocm/rhel9/$ROCM_VERSION/main" >> /etc/yum.repos.d/rocm.repo && \
    echo "enabled=1" >> /etc/yum.repos.d/rocm.repo && \
    echo "gpgcheck=0" >> /etc/yum.repos.d/rocm.repo && \
    dnf install -y llvm clang clang-libs lld && \
    dnf install -y --nodocs --setopt=install_weak_deps=False \
        amd-smi-lib \
        amd-smi \
        miopen-hip \
        rocm-core \
        rocm-hip-libraries \
        rocminfo && \
    dnf clean all && rm -rf /var/cache/yum
# Set the user
USER $USERNAME

ENV PYTHON_VERSION=3.12 \
    PATH=$HOME/.local/bin/:$PATH \
    PYTHONUNBUFFERED=1 \
    ROCM_VERSION=$ROCM_VERSION \
    HIP_VISIBLE_DEVICES=$HIP_VISIBLE_DEVICES \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8 \
    ROCM_PATH=/opt/rocm \
    LD_LIBRARY_PATH=/usr/lib64:/usr/lib:/opt/rocm/lib:/opt/rocm/llvm/lib \
    PATH=/opt/rocm/bin:/opt/rocm/llvm/bin:$PATH

# Stage for llvm-local-true
FROM base AS llvm-local-true
COPY --from=llvm-build /llvm-project/ /llvm-project/

# Stage for llvm-local-false
FROM base AS llvm-local-false
ENV TRITON_OFFLINE_BUILD=NO

# Use intermediate stage selection
FROM llvm-local-${CUSTOM_LLVM}

WORKDIR /opt
# Install dependencies
RUN pip install --upgrade pip
RUN pip install --upgrade setuptools
RUN pip install ninja cmake wheel pybind11 tabulate scipy ninja cmake numpy pyyaml ctypeslib2 matplotlib pandas
RUN pip install --no-cache-dir torch==2.5.1 --index-url https://download.pytorch.org/whl/rocm"${ROCM_VERSION}"
RUN pip install pre-commit
RUN echo "export MAX_JOBS=$(nproc --all)" >> "${HOME}"/.bashrc
# Conditionally set the env vars based on CUSTOM_LLVM
RUN if [ "$CUSTOM_LLVM" = "true" ]; then \
    echo "export LLVM_BUILD_DIR=/llvm-project/build " >> "${HOME}/.bashrc" && \
    echo "export LLVM_INCLUDE_DIRS=/llvm-project/build/include" >> "${HOME}/.bashrc" && \
    echo "export LLVM_LIBRARY_DIR=/llvm-project/build/lib" >> "${HOME}/.bashrc" && \
    echo "export LLVM_SYSPATH=/llvm-project/build" >> "${HOME}/.bashrc"; \
fi
