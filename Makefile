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
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)


mkfile_path=$(abspath $(lastword $(MAKEFILE_LIST)))
source_dir=$(shell dirname "$(mkfile_path)")
triton_path?=${source_dir}
gitconfig_path?="${HOME}/.gitconfig"
USERNAME=triton
NPROC=$(shell nproc)
CUSTOM_LLVM?=false
IMAGE_REPO ?= quay.io/triton-dev-containers
IMAGE_NAME ?= nvidia
CPU_IMAGE_NAME ?= cpu
AMD_IMAGE_NAME ?= amd
TRITON_TAG ?= latest
export CTR_CMD?=$(or $(shell command -v podman), $(shell command -v docker))

##@ Container build.
image-builder-check:
	@if [ -z '$(CTR_CMD)' ] ; then echo '!! ERROR: containerized builds require podman||docker CLI, none found $$PATH' >&2 && exit 1; fi

all: triton-image

triton-image: image-builder-check ## Build the triton devcontainer image
	$(CTR_CMD) build -t $(IMAGE_REPO)/$(IMAGE_NAME):$(TRITON_TAG) --build-arg USERNAME=${USERNAME} --build-arg CUSTOM_LLVM=${CUSTOM_LLVM}\
    --build-arg INSTALL_CUDNN=true  -f Dockerfile.triton .

triton-cpu-image: image-builder-check ## Build the triton-cpu devcontainer image
	$(CTR_CMD) build --no-cache -t $(IMAGE_REPO)/$(CPU_IMAGE_NAME):$(TRITON_TAG) --build-arg USERNAME=${USERNAME} --build-arg CUSTOM_LLVM=${CUSTOM_LLVM}\
    -f Dockerfile.triton-cpu .

triton-amd-image: image-builder-check ## Build the triton devcontainer image
	$(CTR_CMD) build -t $(IMAGE_REPO)/$(AMD_IMAGE_NAME):$(TRITON_TAG) --build-arg USERNAME=${USERNAME} --build-arg CUSTOM_LLVM=${CUSTOM_LLVM}\
    --build-arg INSTALL_CUDNN=true  -f Dockerfile.triton-amd .

triton-run: image-builder-check ## Run the triton devcontainer image
	@if [ "${triton_path}" != "${source_dir}" ]; then \
		volume_arg="-v ${triton_path}:/opt/triton"; \
	else \
		volume_arg=""; \
	fi; \
	if [ -f "${gitconfig_path}" ]; then \
		gitconfig_arg="-v ${HOME}/.gitconfig:/etc/gitconfig"; \
	else \
		gitconfig_arg=""; \
	fi; \
	$(CTR_CMD) run -e USERNAME=${USER} --runtime=nvidia --gpus=all -ti $$volume_arg $$gitconfig_arg $(IMAGE_REPO)/$(IMAGE_NAME):$(TRITON_TAG) bash;

triton-cpu-run: image-builder-check ## Run the triton-cpu devcontainer image
	@if [ "$(triton_path)" != "$(source_dir)" ]; then \
		volume_arg="-v $(triton_path):/opt/triton-cpu"; \
	else \
		volume_arg=""; \
	fi; \
	if [ -f "${gitconfig_path}" ]; then \
		gitconfig_arg="-v ${HOME}/.gitconfig:/etc/gitconfig"; \
	else \
		gitconfig_arg=""; \
	fi; \
	$(CTR_CMD) run -e USERNAME=${USER} -it $$volume_arg $$gitconfig_arg $(IMAGE_REPO)/$(CPU_IMAGE_NAME):$(TRITON_TAG) bash;

triton-amd-run: image-builder-check ## Run the triton-cpu devcontainer image
	@if [ "${triton_path}" != "${source_dir}" ]; then \
		volume_arg="-v ${triton_path}:/opt/triton"; \
	else \
		volume_arg=""; \
	fi; \
	if [ -f "${gitconfig_path}" ]; then \
		gitconfig_arg="-v ${HOME}/.gitconfig:/etc/gitconfig"; \
	else \
		gitconfig_arg=""; \
	fi; \
	HIP_VISIBLE_DEVICES=${HIP_VISIBLE_DEVICES:-0} ; \
	$(CTR_CMD) run -e USERNAME=${USER} --device=/dev/kfd --device=/dev/dri --security-opt seccomp=unconfined \
	--group-add=video --cap-add=SYS_PTRACE --env HIP_VISIBLE_DEVICES=${HIP_VISIBLE_DEVICES} \
	-ti $$volume_arg $$gitconfig_arg $(IMAGE_REPO)/$(AMD_IMAGE_NAME):$(TRITON_TAG) bash;
