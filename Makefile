# SPDX-License-Identifier: BSD-3-Clause
# Copyright (c) 2024 Red Hat Inc

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

AMD_IMAGE_NAME ?=amd
CPU_IMAGE_NAME ?=cpu
CTR_CMD := $(or $(shell command -v podman), $(shell command -v docker))
CUSTOM_LLVM ?=false
DEMO_TOOLS ?= false
HIP_DEVICES := $(or $(HIP_VISIBLE_DEVICES), 0)
IMAGE_REPO ?=quay.io/triton-dev-containers
LLVM_IMAGE_LABEL ?= latest # Need a separate tag so we only update TRITON_TAG for custom builds
LLVM_TAG ?=
mkfile_path :=$(abspath $(lastword $(MAKEFILE_LIST)))
NVIDIA_IMAGE_NAME ?=nvidia
OS := $(shell uname -s)
SELINUXFLAG := $(shell if [ "$(shell getenforce 2> /dev/null)" == "Enforcing" ]; then echo ":z"; fi)
source_dir :=$(shell dirname "$(mkfile_path)")
STRIPPED_CMD := $(shell basename $(CTR_CMD))
torch_version ?=$(shell curl -s https://api.github.com/repos/pytorch/pytorch/releases/latest | grep '"tag_name":' | sed -E 's/.*"tag_name": "v?([^\"]+)".*/\1/')
TRITON_CPU_BACKEND ?=0
TRITON_TAG ?= latest
triton_path ?=$(source_dir)
gitconfig_path ?="$(HOME)/.gitconfig"
USERNAME ?=triton
create_user ?=true
NVIDIA_PROFILING_IMAGE_NAME ?=nvidia-profiling
# NOTE: Requires host build system to have a valid Red Hat Subscription if true
NSIGHT_GUI ?= false
user_path ?=

# Modify image tag if CUSTOM_LLVM is enabled
ifeq ($(CUSTOM_LLVM),true)
    TRITON_TAG := custom-llvm-$(TRITON_TAG)
endif

ifeq ($(TRITON_CPU_BACKEND),1)
    LLVM_IMAGE_LABEL := cpu-$(LLVM_IMAGE_LABEL)
endif

##@ Container Build
.PHONY: image-builder-check
image-builder-check: ## Verify if container runtime is available
	@if [ -z "$(CTR_CMD)" ]; then \
		echo '!! ERROR: containerized builds require podman or docker CLI, none found in $$PATH' >&2; \
		exit 1; \
	fi

.PHONY: all
all: triton-image triton-cpu-image triton-amd-image triton-profiling-image

.PHONY: llvm-image
llvm-image: image-builder-check ## Build the Triton LLVM image
	$(CTR_CMD) build -t $(IMAGE_REPO)/llvm:$(LLVM_IMAGE_LABEL) \
		--build-arg CUSTOM_LLVM=$(CUSTOM_LLVM) \
		--build-arg LLVM_TAG=$(LLVM_TAG) \
		--build-arg TRITON_CPU_BACKEND=$(TRITON_CPU_BACKEND) \
		-f Dockerfile.llvm .

.PHONY: gosu-image
gosu-image: image-builder-check ## Build the Triton gosu image
	$(CTR_CMD) build -t $(IMAGE_REPO)/gosu:latest -f Dockerfile.gosu .

.PHONY: triton-image
triton-image: image-builder-check gosu-image llvm-image ## Build the Triton devcontainer image
	$(CTR_CMD) build -t $(IMAGE_REPO)/$(NVIDIA_IMAGE_NAME):$(TRITON_TAG) \
		--build-arg CUSTOM_LLVM=$(CUSTOM_LLVM) -f Dockerfile.triton .

.PHONY: triton-cpu-image
triton-cpu-image: image-builder-check gosu-image ## Build the Triton CPU image
	$(MAKE) llvm-image CUSTOM_LLVM=$(CUSTOM_LLVM) TRITON_CPU_BACKEND=1 LLVM_IMAGE_LABEL=cpu-latest
	$(CTR_CMD) build -t $(IMAGE_REPO)/$(CPU_IMAGE_NAME):$(TRITON_TAG) \
		--build-arg CUSTOM_LLVM=$(CUSTOM_LLVM) --build-arg TRITON_CPU_BACKEND=1 \
		-f Dockerfile.triton-cpu .

.PHONY: triton-amd-image
triton-amd-image: image-builder-check gosu-image llvm-image ## Build the Triton AMD devcontainer image
	$(CTR_CMD) build -t $(IMAGE_REPO)/$(AMD_IMAGE_NAME):$(TRITON_TAG) \
		--build-arg CUSTOM_LLVM=$(CUSTOM_LLVM) -f Dockerfile.triton-amd .

.PHONY: triton-profiling-image
triton-profiling-image: image-builder-check gosu-image llvm-image ## Build the Triton profiling devcontainer image
	$(CTR_CMD) build -t $(IMAGE_REPO)/$(NVIDIA_PROFILING_IMAGE_NAME):$(TRITON_TAG) \
		--build-arg CUSTOM_LLVM=$(CUSTOM_LLVM) --build-arg NSIGHT_GUI=$(NSIGHT_GUI) \
		-f Dockerfile.triton-profiling .

##@ Container Run
# If you are on an OS that has the user in /etc/passwd then we can pass
# the user from the host to the pod. Otherwise we default to create the
# user inside the container.
# With podman if you aren't creating the user you need to explicitly pass
# the user as --user $(USER) to start the container as that user.
define run_container
	echo "Running container image: $(IMAGE_REPO)/$(strip $(1)):$(TRITON_TAG) with $(CTR_CMD)"
	@if [ "$(triton_path)" != "$(source_dir)" ]; then \
		volume_arg="-v $(triton_path):/workspace/$(strip $(2))$(SELINUXFLAG)"; \
	else \
		volume_arg=""; \
	fi; \
	if [ -n "$(user_path)" ]; then \
		volume_arg+=" -v $(user_path):/workspace/user$(SELINUXFLAG)"; \
	fi; \
	if [ "$(OS)" != "Darwin" ] && ! getent passwd $(USER) > /dev/null && [ "$(create_user)" = "false" ]; then \
		volume_arg+=" -v /etc/passwd:/etc/passwd:ro -v /etc/group:/etc/group:ro"; \
	fi; \
	if [ -f "$(gitconfig_path)" ]; then \
		gitconfig_arg="-v $(gitconfig_path):/etc/gitconfig$(SELINUXFLAG)"; \
	else \
		gitconfig_arg=""; \
	fi; \
	if [ "$(strip $(1))" = "$(AMD_IMAGE_NAME)" ]; then \
		gpu_args="--device=/dev/kfd --device=/dev/dri --security-opt seccomp=unconfined --group-add=video --cap-add=SYS_PTRACE --ipc=host --env HIP_VISIBLE_DEVICES=$(HIP_DEVICES)"; \
	elif [ "$(strip $(1))" = "$(NVIDIA_IMAGE_NAME)" ] || [ "$(strip $(1))" = "$(NVIDIA_PROFILING_IMAGE_NAME)" ]; then \
		if command -v nvidia-ctk >/dev/null 2>&1 && nvidia-ctk cdi list | grep -q "nvidia.com/gpu=all"; then \
			gpu_args="--device nvidia.com/gpu=all"; \
		else \
			gpu_args="--runtime=nvidia --gpus=all"; \
		fi; \
		gpu_args+=" --security-opt label=disable"; \
	fi; \
	if [ "$(strip $(1))" = "$(NVIDIA_PROFILING_IMAGE_NAME)" ] && [ "$(NSIGHT_GUI)" = "false" ]; then \
		profiling_args="--cap-add=SYS_ADMIN"; \
	elif [ "$(strip $(1))" = "$(NVIDIA_PROFILING_IMAGE_NAME)" ] && [ "$(NSIGHT_GUI)" = "true" ]; then \
	 	profiling_args="--cap-add=SYS_ADMIN -e DISPLAY=${DISPLAY} -e WAYLAND_DISPLAY=${WAYLAND_DISPLAY} \
		-e XDG_RUNTIME_DIR=/tmp -v ${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}:/tmp/${WAYLAND_DISPLAY}:ro"; \
	else \
		profiling_args=""; \
	fi ; \
	if [ "$(STRIPPED_CMD)" = "podman" ]; then \
		keep_ns_arg="--userns=keep-id"; \
	else \
		keep_ns_arg=""; \
	fi; \
	if [ "$(DEMO_TOOLS)" = "true" ]; then \
		port_arg="-p 8888:8888"; \
	else \
		port_arg=""; \
	fi; \
	env_vars="-e USERNAME=$(USER) -e TORCH_VERSION=$(torch_version) -e CUSTOM_LLVM=$(CUSTOM_LLVM)" -e DEMO_TOOLS=$(DEMO_TOOLS); \
	if [ "$(create_user)" = "true" ]; then \
		$(CTR_CMD) run -e CREATE_USER=$(create_user) $$env_vars $$port_arg \
		-e USER_UID=`id -u $(USER)` -e USER_GID=`id -g $(USER)` $$gpu_args $$profiling_args $$keep_ns_arg \
		-ti $$volume_arg $$gitconfig_arg $(IMAGE_REPO)/$(strip $(1)):$(TRITON_TAG) bash; \
	elif [ "$(STRIPPED_CMD)" = "docker" ]; then \
		$(CTR_CMD) run --user $(shell id -u):$(shell id -g) $$env_vars $$gpu_args $$profiling_args $$port_arg \
		-ti $$volume_arg $$gitconfig_arg $(IMAGE_REPO)/$(strip $(1)):$(TRITON_TAG) bash; \
	elif [ "$(STRIPPED_CMD)" = "podman" ]; then \
		$(CTR_CMD) run --user $(USER) $$env_vars $$keep_ns_arg $$gpu_args $$profiling_args $$port_arg \
		-ti $$volume_arg $$gitconfig_arg $(IMAGE_REPO)/$(strip $(1)):$(TRITON_TAG) bash; \
	fi
endef

.PHONY: triton-run
triton-run: image-builder-check ## Run the Triton devcontainer image
	$(call run_container, $(NVIDIA_IMAGE_NAME), "triton")

.PHONY: triton-cpu-run
triton-cpu-run: image-builder-check ## Run the Triton CPU devcontainer image
	$(call run_container, $(CPU_IMAGE_NAME), "triton-cpu")

.PHONY: triton-amd-run
triton-amd-run: image-builder-check ## Run the Triton AMD devcontainer image
	$(call run_container, $(AMD_IMAGE_NAME), "triton")

.PHONY: triton-profiling-run
triton-profiling-run: image-builder-check ## Run the Triton devcontainer image
	$(call run_container, $(NVIDIA_PROFILING_IMAGE_NAME), "triton")

##@ Devcontainer

.PHONY: devcontainers
devcontainers: ## Generate all devcontainer.json files
	@echo "Running devcontainer generation..."
	$(MAKE) -C .devcontainer generate

.PHONY: clean-devcontainers
clean-devcontainers: ## Remove generated devcontainer.json files
	$(MAKE) -C .devcontainer clean

.PHONY: devcontainers-help
devcontainers-help: ## Show devcontainer help
	$(MAKE) -C .devcontainer help
