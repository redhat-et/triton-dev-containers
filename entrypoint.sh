#! /bin/bash -e
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
set -euo pipefail

readonly USER=${USERNAME:-triton}
readonly USER_ID=${USER_UID:-1000}
readonly GROUP_ID=${USER_GID:-1000}
readonly CUSTOM_LLVM=${CUSTOM_LLVM:-}
readonly AMD=${AMD:-}
readonly TRITON_CPU_BACKEND=${TRITON_CPU_BACKEND:-}
readonly ROCM_VERSION=${ROCM_VERSION:-}
readonly HIP_VISIBLE_DEVICES=${HIP_VISIBLE_DEVICES:-}
readonly INSTALL_CUDNN=${INSTALL_CUDNN:-}
readonly CREATE_USER=${CREATE_USER:-false}
CLONED=0
export_cmd=""

navigate() {
    if [ -n "$TRITON_CPU_BACKEND" ] && [ "$TRITON_CPU_BACKEND" -eq 1 ]; then
        if [ -d "/workspace/triton-cpu" ]; then
            cd "/workspace/triton-cpu" || exit 1
            export TRITON_DIR="/workspace/triton-cpu"
        fi
    else
        if [ -d "/workspace/triton" ]; then
            cd "/workspace/triton" || exit 1
            export TRITON_DIR="/workspace/triton"
        fi
    fi
}

install_dependencies() {
    echo "#############################################################################"
    echo "################### Cloning the Triton repos (if needed)... #################"
    echo "#############################################################################"
    if [ -n "$TRITON_CPU_BACKEND" ] && [ "$TRITON_CPU_BACKEND" -eq 1 ]; then
        if [ ! -d "/workspace/triton-cpu" ]; then
            echo "/workspace/triton-cpu not found. Cloning repository..."
            git clone https://github.com/triton-lang/triton-cpu.git "/workspace/triton-cpu"
            CLONED=1
        fi
    else
        if [ ! -d "/workspace/triton" ]; then
            echo "/workspace/triton not found. Cloning repository..."
            git clone https://github.com/triton-lang/triton.git "/workspace/triton"
            CLONED=1
        fi
    fi

    navigate

    if [ "$CLONED" -eq 1 ]; then
        git submodule init
        git submodule update
    fi

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
    if [ -f "${TRITON_DIR}/python/requirements.txt" ]; then
        pip install --no-cache-dir -r "${TRITON_DIR}/python/requirements.txt"
    fi
    pip install tabulate scipy ninja cmake wheel pybind11
    pip install numpy pyyaml ctypeslib2 matplotlib pandas

    if [ "$CLONED" -eq 1 ]; then
        echo "###############################################################################"
        echo "#####################Installing pre-commit dependencies...#####################"
        echo "###############################################################################"
        pip install pre-commit

        pre-commit install
    fi

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

# Function to update MAX_UID and MAX_GID in /etc/login.defs
update_max_uid_gid() {
    local current_max_uid
    local current_max_gid
    local current_min_uid
    local current_min_gid

    # Get current max UID and GID from /etc/login.defs
    current_max_uid=$(grep "^UID_MAX" /etc/login.defs | awk '{print $2}')
    current_max_gid=$(grep "^GID_MAX" /etc/login.defs | awk '{print $2}')
    current_min_uid=$(grep "^UID_MIN" /etc/login.defs | awk '{print $2}')
    current_min_gid=$(grep "^GID_MIN" /etc/login.defs | awk '{print $2}')

    # Check and update MAX_UID if necessary
    if [ "$USER_ID" -gt "$current_max_uid" ]; then
        echo "Updating UID_MAX from $current_max_uid to $USER_ID"
        sed -i "s/^UID_MAX.*/UID_MAX $USER_ID/" /etc/login.defs
    fi

    # Check and update MAX_GID if necessary
    if [ "$GROUP_ID" -gt "$current_max_gid" ]; then
        echo "Updating GID_MAX from $current_max_gid to $GROUP_ID"
        sed -i "s/^GID_MAX.*/GID_MAX $GROUP_ID/" /etc/login.defs
    fi

    # Check and update MIN_UID if necessary
    if [ "$USER_ID" -lt "$current_min_uid" ]; then
        echo "Updating UID_MIN from $current_min_uid to $USER_ID"
        sed -i "s/^UID_MIN.*/UID_MIN $USER_ID/" /etc/login.defs
    fi

    # Check and update MIN_GID if necessary
    if [ "$GROUP_ID" -lt "$current_min_gid" ]; then
        echo "Updating GID_MIN from $current_min_gid to $GROUP_ID"
        sed -i "s/^GID_MIN.*/GID_MIN $GROUP_ID/" /etc/login.defs
    fi
}

export_vars() {
    # Define environment variables to export
    declare -a export_vars=(
        "USERNAME=$USER"
        "USER_UID=$USER_ID"
        "USER_GID=$GROUP_ID"
    )

    if [ -n "$CUSTOM_LLVM" ]; then
        export_vars+=("CUSTOM_LLVM=$CUSTOM_LLVM")
    fi

    if [ -n "$TRITON_CPU_BACKEND" ] && [ "$TRITON_CPU_BACKEND" -eq 1 ]; then
        export_vars+=("TRITON_CPU_BACKEND=$TRITON_CPU_BACKEND")
    fi

    if [ -n "$INSTALL_CUDNN" ]; then
        export_vars+=("INSTALL_CUDNN=$INSTALL_CUDNN")
    fi

    if [ -n "$AMD" ]; then
        export_vars+=("AMD=$AMD")
    fi

    if [ -n "$ROCM_VERSION" ]; then
        export_vars+=("ROCM_VERSION=$ROCM_VERSION")
    fi

    if [ -n "$HIP_VISIBLE_DEVICES" ]; then
        export_vars+=("HIP_VISIBLE_DEVICES=$HIP_VISIBLE_DEVICES")
    fi

    for var in "${export_vars[@]}"; do
        export_cmd+="export $var; "
    done
}

# Check if the USER environment variable is set and not empty
if [ -n "$CREATE_USER" ] && [ "$CREATE_USER" = "true" ]; then
    if [ -n "$USER" ] && [ "$USER" != "root" ] ; then
        update_max_uid_gid
        # Create user if it doesn't exist
        if ! id -u "$USER" >/dev/null 2>&1; then
            echo "Creating user $USER with UID $USER_ID and GID $GROUP_ID"
            ./user.sh -u "$USER" -i "$USER_ID" -g "$GROUP_ID"
        fi

        export_vars

        echo "Switching to user: $USER to install dependencies."
        runuser -u "$USER" -- bash -c "$export_cmd $(declare -f install_dependencies navigate); install_dependencies"
        navigate
        exec gosu "$USER" "$@"
    fi
else
    install_dependencies
    navigate
    exec "$@"
fi
