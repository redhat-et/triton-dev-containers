# Triton Dev Containers

## TL;DR

- **What this repo provides**: Preconfigured development containers
for building and running Triton and Triton-cpu.
- **Who it's for**: Developers working on Triton.
- **Why use it**: Provides isolated, reproducible environments for
development.
- **How to use it**: Mount your Triton directory into the available
containers and start working.

---

## Details

This repository provides development containers preconfigured with
all the necessary tools to build and run Triton and Triton-cpu.
By mounting your Triton directory from the host into the container,
you can continue working with your preferred IDE while keeping build
and runtime tasks isolated within the container environment. This
repo also provides the .devcontainer files that can be used with
the VSCode development container extension. The goal of this repo
is to provide consistent and reproducible development environments
for Triton.

### Available Containers

This repository offers two types of development containers:

1. **Vanilla Containers** – Containers where a development directory
  can be mounted.
2. **Profiling Containers** - Vanilla Containers with profiling tools installed
3. **VSCode DevContainers** – Configured for use with Visual Studio
  Code via the Dev Containers Extension.

### Prerequisites

Before using these containers, ensure you have the following installed:

- **Docker** or **Podman**
- **NVIDIA Container Toolkit** (Required for GPU usage with NVIDIA hardware)
- **AMD ROCm** (Required for GPU usage with AMD hardware)
- **VSCode Dev Container Extension** (Only needed for VSCode dev containers)

> **Note:** If using an NVIDIA GPU, install the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).

> **Note:** The NVIDIA Container Toolkit is not required for `triton-cpu`.

> **Note:** If using an AMD GPU, install the
[ROCm Docker Prerequisites](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/how-to/docker.html).

> **Note:** If using a 'rootless' triton-profiling container, ncu will not work
> without enabling access to the NVIDIA GPU performance counters. Follow this
> [NVIDIA Development Tools Solution](https://developer.nvidia.com/nvidia-development-tools-solutions-err_nvgpuctrperm-permission-issue-performance-counters)

### Supported Hardware

- NVIDIA GPUs
- AMD GPUs
- CPUs

### Using Vanilla Containers

#### Building the triton NVIDIA vanilla container

```sh
make triton-image
```

#### Running the triton NVIDIA vanilla container

```sh
 make triton-run [triton_path=<path-to-triton-on-host>]
```

> **_NOTE_**: if you do not provide `triton_path` the triton repo will be cloned
at container startup time.

> **_NOTE_**: if you do provide a triton_path you should run `git submodule init`
and `git submodule update` on the mounted repo if you haven't already run these
commands.

#### Building the triton-cpu vanilla container

```sh
 make triton-cpu-image
```

#### Running the triton-cpu vanilla container

```sh
 make triton-cpu-run [triton_path=<path-to-triton-on-host>]
```

> **_NOTE_**: if you do not provide `triton_path` the triton-cpu repo will be cloned
at container startup time.

> **_NOTE_**: if you do provide a triton_path you should run `git submodule init`
and `git submodule update` on the mounted repo if you haven't already run these
commands.

#### Building the triton-amd vanilla container

```sh
 make triton-amd-image
```

#### Running the triton-amd vanilla container

```sh
 make triton-amd-run [triton_path=<path-to-triton-on-host>]
```

> **_NOTE_**: if you do not provide `triton_path` the triton repo will be cloned
at container startup time.

> **_NOTE_**: it's also advised that you commit the image after it's completed initialization
`[podman|docker] commit <container_id> quay.io/triton-dev-containers/amd:latest`

> **_NOTE_**: if you do provide a triton_path you should run `git submodule init`
and `git submodule update` on the mounted repo if you haven't already run these
commands.

### Using the Profiling Containers

#### Building the triton NVIDIA profiling container

```sh
make triton-profiling-image
```

> **_NOTE_**: if you provide `NSIGHT_GUI=true` the dependencies required to run
the gui apps will be installed.

#### Running the triton NVIDIA profiling container

```sh
 make triton-profiling-run [triton_path=<path-to-triton-on-host>]
```

> **_NOTE_**: if you do not provide `triton_path` the triton repo will be cloned
at container startup time.

> **_NOTE_**: if you do provide a triton_path you should run `git submodule init`
and `git submodule update` on the mounted repo if you haven't already run these
commands.

> **_NOTE_**: if you provide `NSIGHT_GUI=true` the container will be able to launch
the `nsys-ui` and `ncu-ui` apps.

### Using .devcontainers with VSCODE

Please see the [.devcontainer user guide](./.devcontainer/devcontainer.md)

### Demos

To see the VSCODE devcontainers in action please check out the
[Triton devcontainer vscode demo](https://www.youtube.com/watch?v=ZrCVtV2Bw3s)

To see the vanilla development containers in action please checkout the
[Triton devcontainer demo](https://www.youtube.com/watch?v=kEbN6-pk3sI)

### Why Container-First Development Matters?

Please checkout why container-first development matters
[here](./docs/ContainerFirstDevelopment.md).

### More about the containers

The container images provided by this repo are based on
[RHEL UBI images](https://www.redhat.com/en/blog/introducing-red-hat-universal-base-image).
They support both root and non-root users. For non-root
user support, the user is created at runtime via the container
entrypoint script [entrypoint.sh](./entrypoint.sh).

### Adding packages as a non-root user inside the development containers

To add extra packages to the non-root user container, create a
Dockerfile that extends one of the provided base/vanilla
images:

- quay.io/triton-dev-containers/nvidia
- quay.io/triton-dev-containers/cpu
- quay.io/triton-dev-containers/amd
- quay.io/triton-dev-containers/nvidia-profiling

```dockerfile
FROM quay.io/triton-dev-containers/nvidia:latest

USER 0

RUN dnf update -y && \
    dnf -y install <PACKAGES> && \ #### <==== modify this line to add your packages.
    dnf clean all
```

### Why do the containers install some dependencies at startup time?

Some dependencies are installed at runtime to optimize image size of
the development containers. This allows the images to remain
lightweight while still providing all necessary functionality.
The packages installed at startup time can be found in
[entrypoint.sh](./entrypoint.sh).
