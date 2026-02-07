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
INSTALL_LLVM   ?= skip              # [ source | skip ]
INSTALL_HELION ?= skip              # [ source | release | nightly | skip ]
INSTALL_TORCH  ?= skip              # [ source | release | nightly | test | skip ]
INSTALL_TRITON ?= skip              # [ source | release | skip ]
INSTALL_VLLM   ?= skip              # [ source | release | nightly | skip ]

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
triton_path    ?= $(source_dir)
user_path      ?=
vllm_path      ?=
gitconfig_path ?= $(HOME)/.gitconfig

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
RUNTIME_ARGS := -t $(IMAGE_TAG) -p $(NOTEBOOK_PORT) -j $(MAX_JOBS)

ifneq ($(llvm_path), )
	RUNTIME_ARGS += -s LLVM=$(llvm_path)
endif

ifneq ($(helion_path), )
	RUNTIME_ARGS += -s HELION=$(helion_path)
endif

ifneq ($(torch_path), )
	RUNTIME_ARGS += -s TORCH=$(torch_path)
endif

ifneq ($(triton_path),$(source_dir))
	RUNTIME_ARGS += -s TRITON=$(triton_path)
endif

ifneq ($(user_path), )
	RUNTIME_ARGS += -s USER=$(user_path)
endif

ifneq ($(vllm_path), )
	RUNTIME_ARGS += -s VLLM=$(vllm_path)
endif

ifneq ($(gitconfig_path), )
	RUNTIME_ARGS += -s GITCONFIG=$(gitconfig_path)
endif

ifeq ($(INSTALL_JUPYTER),true)
	RUNTIME_ARGS += -o INSTALL_JUPYTER=true
endif

ifeq ($(INSTALL_NSIGHT),true)
	INSTALL_TOOLS = true
endif

ifeq ($(INSTALL_TOOLS),true)
	RUNTIME_ARGS += -o INSTALL_TOOLS=true
endif

ifneq ($(PIP_HELION_VERSION), )
	RUNTIME_ARGS += -o PIP_HELION_VERSION=$(PIP_HELION_VERSION)
endif

ifneq ($(PIP_TORCH_VERSION), )
	RUNTIME_ARGS += -o PIP_TORCH_VERSION=$(PIP_TORCH_VERSION)
endif

ifneq ($(PIP_TRITON_VERSION), )
	RUNTIME_ARGS += -o PIP_TRITON_VERSION=$(PIP_TRITON_VERSION)
endif

ifneq ($(PIP_VLLM_VERSION), )
	RUNTIME_ARGS += -o PIP_VLLM_VERSION=$(PIP_VLLM_VERSION)
endif

ifneq ($(CUDA_VISIBLE_DEVICES), )
	RUNTIME_ARGS += -o CUDA_VISIBLE_DEVICES=$(CUDA_VISIBLE_DEVICES)
endif

ifneq ($(ROCR_VISIBLE_DEVICES), )
	RUNTIME_ARGS += -o ROCR_VISIBLE_DEVICES=$(ROCR_VISIBLE_DEVICES)
endif

ifneq ($(PIP_TORCH_INDEX_URL), )
	RUNTIME_ARGS += -o PIP_TORCH_INDEX_URL=$(PIP_TORCH_INDEX_URL)
endif

ifneq ($(UV_TORCH_BACKEND), )
	RUNTIME_ARGS += -o UV_TORCH_BACKEND=$(UV_TORCH_BACKEND)
endif

ifneq ($(PIP_VLLM_EXTRA_INDEX_URL), )
	RUNTIME_ARGS += -o PIP_VLLM_EXTRA_INDEX_URL=$(PIP_VLLM_EXTRA_INDEX_URL)
endif

ifneq ($(PIP_VLLM_COMMIT), )
	RUNTIME_ARGS += -o PIP_VLLM_COMMIT=$(PIP_VLLM_COMMIT)
endif

ifneq ($(create_user), )
	RUNTIME_ARGS += -u $(create_user)
endif

define CUDA_RUNTIME_ARGS
	$(RUNTIME_ARGS) \
	-o CUDA_VERSION=$(CUDA_VERSION)
endef

define CPU_RUNTIME_ARGS
	$(RUNTIME_ARGS)
endef

define ROCM_RUNTIME_ARGS
	$(RUNTIME_ARGS) \
	-o ROCM_VERSION=$(ROCM_VERSION)
endef


# Old runtime targets (DEPRECATED)
.PHONY: triton-run
triton-run: triton-cuda-run

.PHONY: triton-amd-run
triton-amd-run: triton-rocm-run


.PHONY: base-run
base-run: ## Run the Base container image
	@./triton-dev-containers.sh $(RUNTIME_ARGS) -d $(BASE_IMAGE_NAME)

.PHONY: cuda-run
cuda-run: ## Run the CUDA container image
	@./triton-dev-containers.sh $(CUDA_RUNTIME_ARGS) -d $(CUDA_IMAGE_NAME)

.PHONY: cpu-run
cpu-run: ## Run the CPU container image
	@./triton-dev-containers.sh $(CPU_RUNTIME_ARGS) -d $(CPU_IMAGE_NAME)

.PHONY: rocm-run
rocm-run: ## Run the ROCm container image
	@./triton-dev-containers.sh $(ROCM_RUNTIME_ARGS) -d $(ROCM_IMAGE_NAME)

.PHONY: helion-cuda-run
helion-cuda-run: ## Run the Helion CUDA container image
	@./triton-dev-containers.sh $(CUDA_RUNTIME_ARGS) -d $(CUDA_IMAGE_NAME) -k helion

.PHONY: helion-cpu-run
helion-cpu-run: ## Run the Helion CPU container image
	@./triton-dev-containers.sh $(CPU_RUNTIME_ARGS) -d $(CPU_IMAGE_NAME) -k helion

.PHONY: helion-rocm-run
helion-rocm-run: ## Run the Helion ROCm container image
	@./triton-dev-containers.sh $(ROCM_RUNTIME_ARGS) -d $(ROCM_IMAGE_NAME) -k helion

.PHONY: triton-cuda-run
triton-cuda-run: ## Run the Triton CUDA container image
	@./triton-dev-containers.sh $(CUDA_RUNTIME_ARGS) -d $(CUDA_IMAGE_NAME) -k triton

.PHONY: triton-cpu-run
triton-cpu-run: ## Run the Triton CPU container image
	@./triton-dev-containers.sh $(CPU_RUNTIME_ARGS) -d $(CPU_IMAGE_NAME) -k triton

.PHONY: triton-rocm-run
triton-rocm-run: ## Run the Triton ROCm container image
	@./triton-dev-containers.sh $(ROCM_RUNTIME_ARGS) -d $(ROCM_IMAGE_NAME) -k triton

.PHONY: torch-cuda-run
torch-cuda-run: ## Run the PyTorch CUDA container image
	@./triton-dev-containers.sh $(CUDA_RUNTIME_ARGS) -d $(CUDA_IMAGE_NAME) -k torch

.PHONY: torch-cpu-run
torch-cpu-run: ## Run the PyTorch CPU container image
	@./triton-dev-containers.sh $(CPU_RUNTIME_ARGS) -d $(CPU_IMAGE_NAME) -k torch

.PHONY: torch-rocm-run
torch-rocm-run: ## Run the PyTorch ROCm container image
	@./triton-dev-containers.sh $(ROCM_RUNTIME_ARGS) -d $(ROCM_IMAGE_NAME) -k torch

.PHONY: vllm-cuda-run
vllm-cuda-run: ## Run the vLLM CUDA container image
	@./triton-dev-containers.sh $(CUDA_RUNTIME_ARGS) -d $(CUDA_IMAGE_NAME) -k vllm

.PHONY: vllm-cpu-run
vllm-cpu-run: ## Run the vLLM CPU container image
	@./triton-dev-containers.sh $(CPU_RUNTIME_ARGS) -d $(CPU_IMAGE_NAME) -k vllm

.PHONY: vllm-rocm-run
vllm-rocm-run: ## Run the vLLM ROCm container image
	@./triton-dev-containers.sh $(ROCM_RUNTIME_ARGS) -d $(ROCM_IMAGE_NAME) -k vllm

##@ Runtime Script Installation
.PHONY: install
install: $(HOME)/.local/bin/triton-dev-containers ## Install the triton-dev-containers.sh runtime script

$(HOME)/.local/bin/triton-dev-containers: triton-dev-containers.sh
	install -m 0750 -D $< $@

.PHONY: uninstall
uninstall: ## Uninstall the triton-dev-containers.sh runtime script
	rm -f $(HOME)/.local/bin/triton-dev-containers
