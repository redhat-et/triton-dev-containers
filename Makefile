# SPDX-License-Identifier: BSD-3-Clause
# Copyright (c) 2026 Red Hat Inc

SHELL := /bin/bash

##@ Help
# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php
.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

#################################################################################
# ------------------------------------------------------------------------------
# System environment and tooling
# ------------------------------------------------------------------------------
CTR_CMD      := $(or $(shell command -v podman), $(shell command -v docker))
STRIPPED_CMD := $(shell basename $(CTR_CMD))
OS           := $(shell uname -s)
mkfile_path  := $(abspath $(lastword $(MAKEFILE_LIST)))
source_dir   := $(dir $(mkfile_path))
SELINUXFLAG  := $(shell if [ "$(shell getenforce 2> /dev/null)" == "Enforcing" ]; then echo ":z"; fi)

# ------------------------------------------------------------------------------
# Buildtime configuration
# ------------------------------------------------------------------------------
WORKSPACE = /workspace

# ------------------------------------------------------------------------------
# Versions
# ------------------------------------------------------------------------------
CENTOS_VERSION    ?= 9
CUDA_VERSION      ?= 12-9
GOSU_VERSION      ?= 1.19
PYTHON_VERSION    ?= 3.12
ROCM_RHEL_VERSION ?= 9.7
ROCM_VERSION      ?= 7.1.1

# ------------------------------------------------------------------------------
# Image naming
# ------------------------------------------------------------------------------
IMAGE_REPO = quay.io/triton-dev-containers

# Image name definitions (clean and extensible)
BASE_IMAGE_NAME = base
CPU_IMAGE_NAME  = cpu
CUDA_IMAGE_NAME = cuda
GOSU_IMAGE_NAME = gosu
ROCM_IMAGE_NAME = rocm

# Image tags
IMAGE_TAG      := centos$(CENTOS_VERSION)

BASE_IMAGE_TAG := $(IMAGE_TAG)
CPU_IMAGE_TAG  := $(IMAGE_TAG)
CUDA_IMAGE_TAG := $(CUDA_VERSION)-$(IMAGE_TAG)
GOSU_IMAGE_TAG := $(GOSU_VERSION)-$(IMAGE_TAG)
ROCM_IMAGE_TAG := $(ROCM_VERSION)-$(IMAGE_TAG)

# ------------------------------------------------------------------------------
# Runtime configuration
# ------------------------------------------------------------------------------
RUNTIME_ARGS ?=

# Set the max number of jobs to use when building a framework
# Use a lower value to decrease ram usage during a build
MAX_JOBS ?= $(shell nproc --all)

# Jupyter notebook server port
NOTEBOOK_PORT ?= 8888

# Install debugging and profiling tools
INSTALL_NSIGHT  ?= false
INSTALL_TOOLS   ?= false
INSTALL_JUPYTER ?= true

# Operation to perform for each framework (default is skip)
INSTALL_LLVM   ?= skip                # [ source | skip ]
INSTALL_HELION ?= skip              # [ source | release | nightly | skip ]
INSTALL_TORCH  ?= skip               # [ source | release | nightly | test | skip ]
INSTALL_TRITON ?= skip              # [ source | release | skip ]
INSTALL_VLLM   ?= skip                # [ source | release | nightly | skip ]

# Framework versions to install from PyPi (latest is default for Torch)
PIP_HELION_VERSION ?=
PIP_TORCH_VERSION  ?=
PIP_TRITON_VERSION ?=
PIP_VLLM_VERSION   ?=

# Device indices (NVIDIA and AMD)
CUDA_VISIBLE_DEVICES ?=
HIP_DEVICES          ?= $(or $(HIP_VISIBLE_DEVICES), 0)
ROCR_VISIBLE_DEVICES ?= $(HIP_DEVICES)

# Source code paths
llvm_path      ?=
helion_path    ?=
torch_path     ?=
triton_path    ?= "$(source_dir)"
user_path      ?=
vllm_path      ?=
gitconfig_path ?= "$(HOME)/.gitconfig"

# Wheel url for PyTorch
PIP_TORCH_INDEX_URL ?=

# Torch backend selector for UV [ auto | cu<cuda version> | rocm<rocm version> | cpu ]
UV_TORCH_BACKEND ?=

# Wheel url for vLLM
PIP_VLLM_EXTRA_INDEX_URL ?=

# vLLM repo commit hash for specific wheel build install
PIP_VLLM_COMMIT ?=

create_user ?= $(USER)

TRITON_CPU_BACKEND ?= 0

USERNAME ?= triton

USE_CCACHE ?= 0

SCRIPTS = $(wildcard scripts/*.sh)

.PHONY: all
all: build-images

##@ Container Build

# $(1) = image name
# $(2) = image tag
# $(3) = podman args
# $(4) = dockerfile name
define build-image
	@echo Building image: $(IMAGE_REPO)/$(1):$(2)
	$(CTR_CMD) build -t $(IMAGE_REPO)/$(1):$(2) \
		$(3) -f $(4) .
endef

# Old build targets (DEPRECATED)
.PHONY: triton-image
triton-image: cuda-image

.PHONY: triton-cpu-image
triton-cpu-image: cpu-image

.PHONY: triton-amd-image
triton-amd-image: rocm-image

.PHONY: build-images
build-images: cuda-image cpu-image rocm-image ## Build all container images

define base_image_build_args
--build-arg CENTOS_VERSION=$(CENTOS_VERSION) \
--build-arg GOSU_VERSION=$(GOSU_VERSION) \
--build-arg PYTHON_VERSION=$(PYTHON_VERSION) \
--build-arg WORKSPACE=$(WORKSPACE)
endef

.PHONY: base-image
base-image: dockerfiles/Dockerfile $(SCRIPTS) ## Build the Base container image
	$(call build-image,$(BASE_IMAGE_NAME),$(BASE_IMAGE_TAG),$(base_image_build_args),$<)

define image_build_args
--build-arg BASE_IMAGE_NAME=$(BASE_IMAGE_NAME) \
--build-arg BASE_IMAGE_TAG=$(BASE_IMAGE_TAG)
endef

.PHONY: cuda-image
cuda-image: dockerfiles/Dockerfile.cuda | base-image ## Build a CUDA container image
	$(call build-image,$(CUDA_IMAGE_NAME),$(CUDA_IMAGE_TAG),$(image_build_args) \
		--build-arg BUILD_CUDA_VERSION=$(CUDA_VERSION),$<)

.PHONY: cpu-image
cpu-image: dockerfiles/Dockerfile.cpu |  base-image ## Build a CPU container image
	$(call build-image,$(CPU_IMAGE_NAME),$(CPU_IMAGE_TAG),$(image_build_args),$<)

.PHONY: rocm-image
rocm-image: dockerfiles/Dockerfile.rocm | base-image ## Build a ROCm container image
	$(call build-image,$(ROCM_IMAGE_NAME),$(ROCM_IMAGE_TAG),$(image_build_args) \
		--build-arg BUILD_ROCM_VERSION=$(ROCM_VERSION) \
		--build-arg BUILD_ROCM_RHEL_VERSION=$(ROCM_RHEL_VERSION),$<)

##@ Container Run
# If you are on an OS that has the user in /etc/passwd then we can pass
# the user from the host to the pod. Otherwise we default to create the
# user inside the container.
# With podman if you aren't creating the user you need to explicitly pass
# the user as --user $(USER) to start the container as that user.
define run_container
	echo "Running container image: $(IMAGE_REPO)/$(strip $(1)):$(2) with $(CTR_CMD)"
	@if [ "$(triton_path)" != "$(source_dir)" ]; then \
		volume_arg="-v $(triton_path):/workspace/$(strip $(3))$(SELINUXFLAG)"; \
	else \
		volume_arg=""; \
	fi; \
	if [ -n "$(llvm_path)" ]; then \
		if [ -d "$(llvm_path)" ]; then \
			volume_arg+=" -v $(llvm_path):/workspace/llvm-project$(SELINUXFLAG)"; \
		else \
			echo "ERROR: llvm_path does not exist: $(llvm_path)" >&2; \
			exit 1; \
		fi; \
	fi; \
	if [ -n "$(torch_path)" ]; then \
		if [ -d "$(torch_path)" ]; then \
			volume_arg+=" -v $(torch_path):/workspace/torch$(SELINUXFLAG)"; \
		else \
			echo "ERROR: torch_path does not exist: $(torch_path)" >&2; \
			exit 1; \
		fi; \
	fi; \
	if [ -n "$(helion_path)" ]; then \
		if [ -d "$(helion_path)" ]; then \
			volume_arg+=" -v $(helion_path):/workspace/helion$(SELINUXFLAG)"; \
		else \
			echo "ERROR: helion_path does not exist: $(helion_path)" >&2; \
			exit 1; \
		fi; \
	fi; \
	if [ -n "$(vllm_path)" ]; then \
		if [ -d "$(vllm_path)" ]; then \
			volume_arg+=" -v $(vllm_path):/workspace/vllm$(SELINUXFLAG)"; \
		else \
			echo "ERROR: vllm_path does not exist: $(vllm_path)" >&2; \
			exit 1; \
		fi; \
	fi; \
	if [ -n "$(user_path)" ]; then \
		if [ -d "$(user_path)" ]; then \
			volume_arg+=" -v $(user_path):/workspace/user$(SELINUXFLAG)"; \
		else \
			echo "ERROR: user_path does not exist: $(user_path)" >&2; \
			exit 1; \
		fi; \
	fi; \
	if [ "$(OS)" != "Darwin" ] && ! getent passwd $(USER) > /dev/null; then \
		volume_arg+=" -v /etc/passwd:/etc/passwd:ro -v /etc/group:/etc/group:ro"; \
	fi; \
	if [ -f "$(gitconfig_path)" ]; then \
		gitconfig_arg="-v $(gitconfig_path):/etc/gitconfig$(SELINUXFLAG)"; \
	else \
		gitconfig_arg=""; \
	fi; \
	if [ "$(strip $(1))" = "$(ROCM_IMAGE_NAME)" ]; then \
		gpu_args="--device=/dev/kfd --device=/dev/dri --security-opt seccomp=unconfined --group-add=video --cap-add=SYS_PTRACE --ipc=host --env HIP_VISIBLE_DEVICES=$(HIP_DEVICES)"; \
	elif [ "$(strip $(1))" = "$(CUDA_IMAGE_NAME)" ]; then \
		if command -v nvidia-ctk >/dev/null 2>&1 && nvidia-ctk cdi list | grep -q "nvidia.com/gpu=all"; then \
			gpu_args="--device nvidia.com/gpu=all"; \
		else \
			gpu_args="--runtime=nvidia --gpus=all"; \
		fi; \
		gpu_args+=" --security-opt label=disable"; \
		if [ "$(INSTALL_NSIGHT)" = "true" ]; then \
			profiling_args="--privileged --cap-add=SYS_ADMIN -e INSTALL_NSIGHT=${INSTALL_NSIGHT} -e DISPLAY=${DISPLAY} -e WAYLAND_DISPLAY=${WAYLAND_DISPLAY} -e XDG_RUNTIME_DIR=/tmp -v ${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}:/tmp/${WAYLAND_DISPLAY}:ro"; \
		else \
			profiling_args=""; \
		fi; \
	else \
		profiling_args=""; \
	fi; \
	if [ "$(STRIPPED_CMD)" = "podman" ]; then \
		keep_ns_arg="--userns=keep-id"; \
	else \
		keep_ns_arg=""; \
	fi; \
	if [ "$(INSTALL_JUPYTER)" = "true" ]; then \
		port_arg="-p ${NOTEBOOK_PORT}:${NOTEBOOK_PORT}"; \
	else \
		port_arg=""; \
	fi; \
	env_vars="-e USERNAME=$(USER) -e USER_UID=`id -u $(USER)` -e USER_GID=`id -g $(USER)` -e TORCH_VERSION=$(torch_version) -e INSTALL_LLVM=$(INSTALL_LLVM) -e INSTALL_TOOLS=$(INSTALL_TOOLS) -e INSTALL_JUPYTER=$(INSTALL_JUPYTER) -e NOTEBOOK_PORT=$(NOTEBOOK_PORT) -e INSTALL_HELION=$(INSTALL_HELION) -e INSTALL_TORCH=$(INSTALL_TORCH) -e INSTALL_TRITON=$(INSTALL_TRITON) -e INSTALL_VLLM=$(INSTALL_VLLM) -e USE_CCACHE=$(USE_CCACHE) -e MAX_JOBS=$(MAX_JOBS)"; \
	if [ "$(STRIPPED_CMD)" = "docker" ]; then \
		$(CTR_CMD) run $$env_vars $$gpu_args $$profiling_args $$port_arg \
		-ti $$volume_arg $$gitconfig_arg $(IMAGE_REPO)/$(strip $(1)):$(2) bash; \
	elif [ "$(STRIPPED_CMD)" = "podman" ]; then \
		$(CTR_CMD) run $$env_vars $$keep_ns_arg $$gpu_args $$profiling_args $$port_arg \
		-ti $$volume_arg $$gitconfig_arg $(IMAGE_REPO)/$(strip $(1)):$(2) bash; \
	fi
endef

# Old runtime targets (DEPRECATED)
.PHONY: triton-run
triton-run: triton-cuda-run

.PHONY: triton-amd-run
triton-amd-run: triton-rocm-run


.PHONY: triton-cuda-run
triton-cuda-run: ## Run the Triton devcontainer image
	$(call run_container,$(CUDA_IMAGE_NAME),$(CUDA_IMAGE_TAG),"triton")

.PHONY: triton-cpu-run
triton-cpu-run: ## Run the Triton CPU devcontainer image
	$(call run_container,$(CPU_IMAGE_NAME),$(CPU_IMAGE_TAG),"triton-cpu")

.PHONY: triton-rocm-run
triton-rocm-run: ## Run the Triton AMD devcontainer image
	$(call run_container,$(ROCM_IMAGE_NAME),$(ROCM_IMAGE_TAG),"triton")
