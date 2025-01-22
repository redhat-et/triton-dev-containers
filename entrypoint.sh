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

# Function to clone repo and install dependencies
install_dependencies() {
    if [ -n "$TRITON_CPU_BACKEND" ] && [ "$TRITON_CPU_BACKEND" -eq 1 ]; then
        if [ ! -d "/opt/triton-cpu" ]; then
            echo "/opt/triton-cpu not found. Cloning repository..."
            git clone https://github.com/triton-lang/triton-cpu.git /opt/triton-cpu
            cd /opt/triton-cpu
        fi
    else
        if [ ! -d "/opt/triton" ]; then
            echo "/opt/triton not found. Cloning repository..."
            git clone https://github.com/triton-lang/triton.git /opt/triton
            cd /opt/triton
        fi
    fi


    git submodule init
    git submodule update

    echo "Installing Python dependencies..."
    pip install --upgrade pip
    if [ -n "$INSTALL_CUDNN" ] && [ "$INSTALL_CUDNN" = "true" ]; then
        python3 -m pip install nvidia-cudnn-cu12;
    fi
    pip install pre-commit
    pip install torch numpy matplotlib pandas tabulate scipy ninja cmake wheel pybind11
    pre-commit install
}

# Check if the USERNAME environment variable is set and not empty
if [ -n "$USERNAME" ] && [ "$USERNAME" != "root" ]; then
    # Create user if it doesn't exist

    if ! id -u "$USER" >/dev/null 2>&1; then
        echo "Creating user $USER with UID $USER_ID and GID $GROUP_ID"
        ./user.sh -u $USER -g $USER_ID
    fi

   # Run the installation as the new user
    echo "Switching to user: $USER to install dependencies."
    runuser -u "$USER" -- bash -c "$(declare -f install_dependencies); install_dependencies"

    # Switch to the new user and execute the original command
    exec runuser -u "$USER" -- "$@"
else

    # Install dependencies
    install_dependencies

    # Execute the provided command
    exec "$@"
fi
