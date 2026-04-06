# Triton Dev Containers

## TL;DR

- **What this repo provides**: Preconfigured development containers for
building and running Triton, Triton-cpu, PyTorch, Helion and vLLM.
- **Who it's for**: Developers working on Triton, PyTorch, Helion and vLLM.
- **Why use it**: Provides isolated, reproducible environments for
development.
- **How to use it**: Mount your Triton, PyTorch, Helion and/or vLLM
source directory into the available containers and start working.

---

## Details

This repository provides development containers preconfigured with all the
necessary tools to build and run Triton, Triton-cpu, PyTorch, Helion and
vLLM. By mounting your source directory from the host into the container,
you can continue working with your preferred IDE while keeping build and
runtime tasks isolated within the container environment. This repo also
provides the .devcontainer files that can be used with the VSCode
development container extension. The goal of this repo is to provide
consistent and reproducible development environments for Triton.

### Available Containers

This repository offers two types of development containers:

1. **Vanilla Containers** – Containers where a development directory
  can be mounted.
2. **VSCode DevContainers** – Configured for use with Visual Studio
  Code via the Dev Containers Extension.

### Prerequisites

Before using these containers, ensure you have the following installed:

- **Docker** or **Podman**
- **NVIDIA Container Toolkit** (Required for GPU usage with NVIDIA hardware)
- **AMD ROCm** (Required for GPU usage with AMD hardware)
- **VSCode Dev Container Extension** (Only needed for VSCode dev containers)

> **Note:** If using an NVIDIA GPU, install the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).

> **Note:** If using an AMD GPU, install the
[ROCm Docker Prerequisites](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/how-to/docker.html).

> **Note:** If using a 'rootless' container, the NVIDIA NSight Compute
application will not work without enabling access to the NVIDIA GPU
performance counters. Follow this
[NVIDIA Development Tools Solution](https://developer.nvidia.com/nvidia-development-tools-solutions-err_nvgpuctrperm-permission-issue-performance-counters)

### Supported Hardware

- NVIDIA GPUs
- AMD GPUs
- CPUs

---

## Vanilla Containers

---

### Building

#### Options

Arguments that can be added to the build commands below, i.e. `OPTION=VALUE`.

- `CUDA_VERSION`
  - Use the CUDA RPM package version, i.e. `12-9`
- `GOSU_VERSION`
  - Check the gosu GitHub for the desired release
  - <https://github.com/tianon/gosu>
- `PYTHON_VERSION`
  - Use the desired RPM package version, i.e. `3.12`
- `ROCM_VERSION`
  - Use the ROCm RPM package version, i.e. `6.3.4`
- `CENTOS_VERSION`
  - CentOS Stream image version to use, i.e. `10`

#### All of the container images

```sh
make build-images [OPTIONS]
```

#### Base container

```sh
make base-image [OPTIONS]
```

#### NVIDIA CUDA container

```sh
make cuda-image [OPTIONS]
```

#### CPU container

```sh
 make cpu-image [OPTIONS]
```

#### AMD ROCm container

```sh
 make rocm-image [OPTIONS]
```

---

### Running

#### Options

Arguments that can be added to the run commands below, i.e. `OPTION=VALUE`.

- `CUDA_VERSION`
  - Use the CUDA RPM package version, i.e. `12-9`
  - Specifies the CUDA image to use
- `ROCM_VERSION`
  - Specifies the ROCm image to use
  - Use the ROCm RPM package version, i.e. `6.3.4`
- `CENTOS_VERSION`
  - CentOS Stream image version to use
- `MAX_JOBS`
  - Number of cores to use when building Triton, PyTorch, Helion or vLLM
  - Default is the `nproc --all`
  - NOTE: Use a lower value if builds cause the host to run out of memory
- `CUDA_VISIBLE_DEVICES`
  - Used to specify the CUDA device index(s) to use, i.e. `0,1`
- `ROCR_VISIBLE_DEVICES`
  - Used to specify the ROCm device index(s) or UUID(s) to use, i.e. `0,GPU-<UUID>`
- `NOTEBOOK_PORT`
  - HTTP port to expose and use for the Jupyter notebook server
- `INSTALL_TOOLS`
  - Install extra tools, such as profiling tools like NVIDIA's Nsight
- `INSTALL_JUPYTER`
  - Enabled by default, so set to `false` to not install the server
- `INSTALL_LLVM`
  - Default is to `skip`
  - Set to `source` to install build deps and download the source if not
      passed in as a volume using `llvm_path=/path/to/source`
- `INSTALL_HELION`
  - Default is to `skip`
  - Set to `source` to install build deps and download the source if not
      passed in as a volume using `helion_path=/path/to/source`
  - Set to `release` or `nightly` to install the wheel
- `INSTALL_TRITON`
  - Default is to `skip`
  - Set to `source` to install build deps and download the source if not
      passed in as a volume using `triton_path=/path/to/source`
  - Set to `release` to install the wheel
- `INSTALL_TORCH`
  - Default is to `skip`
  - Set to `source` to install build deps and download the source if not
      passed in as a volume using `torch_path=/path/to/source`
  - Set to `release`, `nightly`, `test` to install the wheel
- `INSTALL_VLLM`
  - Default is to `skip`
  - Set to `source` to install build deps and download the source if not
      passed in as a volume using `vllm_path=/path/to/source`
  - Set to `release` or `nightly` to install the wheel
- `llvm_path`
  - Local path to LLVM project source to be mounted at `/workspace/llvm-project`
      within the container
- `helion_path`
  - Local path to Helion source to be mounted at `/workspace/helion` within
      the container
- `triton_path`
  - Local path to Triton source to be mounted at `/workspace/triton` within
      the container
- `torch_path`
  - Local path to PyTorch source to be mounted at `/workspace/torch` within
      the container
- `vllm_path`
  - Local path to vLLM source to be mounted at `/workspace/vllm` within
      the container
- `user_path`
  - General use option to mount a host path into the container at
      `/workspace/user`
- `PIP_TORCH_VERSION`
  - Specify the wheel version to install, i.e. `torch==<version>`
- `PIP_HELION_VERSION`
  - Specify the wheel version to install, i.e. `helion==<version>`
- `PIP_TRITON_VERSION`
  - Specify the wheel version to install, i.e. `triton==<version>`
- `PIP_VLLM_VERSION`
  - Specify the wheel version to install, i.e. `vllm==<version>`
- `gitconfig_path`
  - Default is `~/.gitconfig`, use to specify a different gitconfig file path
- `PIP_TORCH_INDEX_URL`
  - Default is `https://download.pytorch.org/whl`
  - Specify a URL to install the torch wheel from
- `PIP_VLLM_EXTRA_INDEX_URL`
  - Same as the torch index url above except for the vLLM wheels
- `PIP_VLLM_COMMIT`
  - vLLM's default index url can install specific git commit builds, specify
      the commit hash you would like to install here
- `UV_TORCH_BACKEND`
  - Specify the torch backend to install for the `release` target of Triton and vLLM
  - CUDA specifies `cu<cuda version>`
  - ROCm specifies `rocm<rocm version>`
  - CPU specifies `cpu`
  - Can use `auto` to let `uv` select the appropriate backend
- `create_user`
  - Default is the host username
  - Used to specify the username used inside the container

#### NVIDIA CUDA containers

##### Base

```sh
 make cuda-run [OPTIONS]
```

##### Triton

```sh
 make triton-cuda-run [OPTIONS]
```

##### PyTorch

```sh
 make torch-cuda-run [OPTIONS]
```

##### Helion

```sh
 make helion-cuda-run [OPTIONS]
```

##### vLLM

```sh
 make vllm-cuda-run [OPTIONS]
```

#### CPU container

##### Base

```sh
 make cpu-run [OPTIONS]
```

##### PyTorch

```sh
 make torch-cpu-run [OPTIONS]
```

##### Triton

```sh
 make triton-cpu-run [OPTIONS]
```

##### Helion

```sh
 make helion-cpu-run [OPTIONS]
```

##### vLLM

```sh
 make vllm-cpu-run [OPTIONS]
```

#### AMD ROCm container

##### Base

```sh
 make rocm-run [OPTIONS]
```

##### Triton

```sh
 make triton-rocm-run [OPTIONS]
```

##### PyTorch

```sh
 make torch-rocm-run [OPTIONS]
```

##### Helion

```sh
 make helion-rocm-run [OPTIONS]
```

##### vLLM

```sh
 make vllm-rocm-run [OPTIONS]
```

---

## Using .devcontainers with VSCODE

Please see the [.devcontainer user guide](./.devcontainer/devcontainer.md)

---

## Demos

To see the VSCODE devcontainers in action please check out the
[Triton devcontainer vscode demo](https://www.youtube.com/watch?v=ZrCVtV2Bw3s)

To see the vanilla development containers in action please checkout the
[Triton devcontainer demo](https://www.youtube.com/watch?v=kEbN6-pk3sI)

## Why Container-First Development Matters?

Please checkout [why container-first development matters](./docs/ContainerFirstDevelopment.md).

## More about the containers

The container images provided by this repo are based on
[RHEL UBI images](https://www.redhat.com/en/blog/introducing-red-hat-universal-base-image).
They support both root and non-root users. For non-root
user support, the user is created at runtime via the container
`setup_user` script [setup_user.sh](./scripts/setup_user.sh).

To install additional software, `sudo` has been added and the user given
non-passworded usage of it.

## Why do the containers install some dependencies at startup time?

Some dependencies are installed at runtime to optimize image size of
the development containers. This allows the images to remain
lightweight while still providing all necessary functionality.
The packages installed at startup time can be found in
[install_software.sh](./scripts/install_software.sh).

## Using the containers as a base for a customized container

Use the `setup` script [setup.sh](./scripts/setup.sh) to run the initial container
configuration, like user creation and base software installation. It will also
run the `setup_<framework>` scripts if the `INSTALL_<FRAMEWORK>` variables have been
set. By default they are all set to `skip` and won't be run.

Use the `setup_<framework>` scripts to install or setup the container to build
the target source. Framework refers to triton, helion, torch, llvm, and vllm.
The scripts can install the wheel packages or download the source and install
build dependencies.

Setup Framework scripts:

- [setup_helion.sh](./scripts/setup_helion.sh)
- [setup_llvm.sh](./scripts/setup_llvm.sh)
- [setup_torch.sh](./scripts/setup_torch.sh)
- [setup_triton.sh](./scripts/setup_triton.sh)
- [setup_vllm.sh](./scripts/setup_vllm.sh)
