#!/bin/bash
#
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

USER=${USERNAME:-triton}
USER_ID=${USER_UID:-1000}
GROUP_ID=${USER_GID:-1000}

navigate() {
    if [ -n "$TRITON_CPU_BACKEND" ] && [ "$TRITON_CPU_BACKEND" -eq 1 ]; then
        if [ -d "/opt/triton-cpu" ]; then
            cd /opt/triton-cpu || exit 1
        fi
    else
        if [ -d "/opt/triton" ]; then
            cd /opt/triton || exit 1
        fi
    fi
}
# Function to clone repo and install dependencies
install_dependencies() {
    echo "#############################################################################"
    echo "################### Cloning the Triton repos (if needed)... #################"
    echo "#############################################################################"
    if [ -n "$TRITON_CPU_BACKEND" ] && [ "$TRITON_CPU_BACKEND" -eq 1 ]; then
        if [ ! -d "/opt/triton-cpu" ]; then
            echo "/opt/triton-cpu not found. Cloning repository..."
            git clone https://github.com/triton-lang/triton-cpu.git /opt/triton-cpu
        fi
    else
        if [ ! -d "/opt/triton" ]; then
            echo "/opt/triton not found. Cloning repository..."
            git clone https://github.com/triton-lang/triton.git /opt/triton
        fi
    fi

    navigate

    git submodule init
    git submodule update

    echo "#############################################################################"
    echo "##################### Installing Python dependencies... #####################"
    echo "#############################################################################"
    pip install --upgrade pip

    if [ -n "$INSTALL_CUDNN" ] && [ "$INSTALL_CUDNN" = "true" ]; then
        echo "###########################################################################"
        echo "##################### Installing CUDA dependencies... #####################"
        echo "###########################################################################"
        python3 -m pip install nvidia-cudnn-cu12;
    fi

    if [ -n "$AMD" ] && [ "$AMD" = "true" ]; then
        echo "###########################################################################"
        echo "##################### Installing ROCm dependencies... #####################"
        echo "###########################################################################"
        pip install --no-cache-dir torch==2.5.1 --index-url https://download.pytorch.org/whl/rocm"${ROCM_VERSION}"
    else
        pip install torch
    fi

    echo "#############################################################################"
    echo "##################### Installing Triton dependencies... #####################"
    echo "#############################################################################"
    pip install tabulate scipy ninja cmake wheel pybind11
    pip install numpy pyyaml ctypeslib2 matplotlib pandas

    echo "###############################################################################"
    echo "#####################Installing pre-commit dependencies...#####################"
    echo "###############################################################################"
    pip install pre-commit

    pre-commit install

    if [ -n "$CUSTOM_LLVM" ] && [ "$CUSTOM_LLVM" = "true" ]; then
        echo "################################################################"
        echo "##################### CUSTOM LLVM BUILD... #####################"
        echo "################################################################"
        echo "export LLVM_BUILD_DIR=/llvm-project/build " >> "${HOME}/.bashrc" && \
        echo "export LLVM_INCLUDE_DIRS=/llvm-project/build/include" >> "${HOME}/.bashrc" && \
        echo "export LLVM_LIBRARY_DIR=/llvm-project/build/lib" >> "${HOME}/.bashrc" && \
        echo "export LLVM_SYSPATH=/llvm-project/build" >> "${HOME}/.bashrc";
        declare -a llvm_vars=(
            "LLVM_BUILD_DIR=/llvm-project/build"
            "LLVM_INCLUDE_DIRS=/llvm-project/build/include"
            "LLVM_LIBRARY_DIR=/llvm-project/build/lib"
            "TRITON_CPU_BACKEND=/llvm-project/build"
        )
        for var in "${llvm_vars[@]}"; do
            export var
        done
    fi
}

# Check if the USER environment variable is set and not empty
if [ -n "$USER" ] && [ "$USER" != "root" ]; then
    # Create user if it doesn't exist
    if ! id -u "$USER" >/dev/null 2>&1; then
        echo "Creating user $USER with UID $USER_ID and GID $GROUP_ID"
        ./user.sh -u "$USER_ID" -g "$GROUP_ID"
    fi

    # Define environment variables to export
    declare -a export_vars=(
        "USERNAME=$USER"
        "USER_UID=$USER_ID"
        "USER_GID=$GROUP_ID"
        "TRITON_CPU_BACKEND=$TRITON_CPU_BACKEND"
        "INSTALL_CUDNN=$INSTALL_CUDNN"
        "CUSTOM_LLVM=$CUSTOM_LLVM"
        "AMD=$AMD"
        "ROCM_VERSION=$ROCM_VERSION"
    )

    # Only add HIP_VISIBLE_DEVICES if it's explicitly set
    if [ -n "$HIP_VISIBLE_DEVICES" ]; then
        export_vars+=("HIP_VISIBLE_DEVICES=$HIP_VISIBLE_DEVICES")
    fi

    export_cmd=""
    for var in "${export_vars[@]}"; do
        export_cmd+="export $var; "
    done

    echo "Switching to user: $USER to install dependencies."
    runuser -u "$USER" -- bash -c "$export_cmd $(declare -f install_dependencies navigate); install_dependencies"
    navigate
    exec gosu "$USER" "$@"
else
    install_dependencies
    navigate
    exec "$@"
fi
