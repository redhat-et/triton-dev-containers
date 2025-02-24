# triton-dev-container

This guide provides step-by-step instructions for using a container
preconfigured with all the tools necessary to build and run Triton.
By mounting the Triton directory from your host into the development
container, you can continue working with your favorite IDE while keeping
all building and running tasks isolated within the container.

This repo provides 2 different flavours of development containers:

1. Vanilla containers into which a development directory can be mounted.

1. devcontainers for use with VSCODE.

## Prerequisites

- **Docker** or **Podman**
- **NVIDIA Container Toolkit for GPU Usage**
- **AMD ROCm for GPU Usage**

> **_NOTE_**: If you are using an NVIDIA GPU, you also need to complete the steps
  to install the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).

> **_NOTE_**: NVIDIA Container Toolkit is not required for `triton-cpu`.

## Supported Hardware

- NVIDIA GPUs
- CPUs
- AMD GPUs

## Building the triton NVIDIA vanilla container

```sh
 make triton-image
```

## Running the triton NVIDIA vanilla container

```sh
 make triton-run [triton_path=<path-to-triton-on-host>]
```

> **_NOTE_**: if you do not provide `triton_path` the triton repo will be cloned
at container startup time.

> **_NOTE_**: if you do provide a triton_path you should run `git submodule init`
and `git submodule update` on the mounted repo if you haven't already run these
commands.

## Building the triton-cpu vanilla container

```sh
 make triton-cpu-image
```

## Running the triton-cpu vanilla container

```sh
 make triton-cpu-run [triton_path=<path-to-triton-on-host>]
```

> **_NOTE_**: if you do not provide `triton_path` the triton-cpu repo will be cloned
at container startup time.

> **_NOTE_**: if you do provide a triton_path you should run `git submodule init`
and `git submodule update` on the mounted repo if you haven't already run these
commands.

## Building the triton-amd vanilla container

```sh
 make triton-amd-image
```

## Running the triton-amd vanilla container

```sh
 make triton-amd-run [triton_path=<path-to-triton-on-host>]
```

> **_NOTE_**: if you do not provide `triton_path` the triton-cpu repo will be cloned
at container startup time.

> **_NOTE_**: it's also advised that you commit the image after it's completed initialization
`[podman|docker] commit <container_id> quay.io/triton-dev-containers/amd:latest`

> **_NOTE_**: if you do provide a triton_path you should run `git submodule init`
and `git submodule update` on the mounted repo if you haven't already run these
commands.

## Using .devcontainers with VSCODE

Please see the [.devcontainer user guide](./.devcontainer/devcontainer.md)

## Demos

To see the VSCODE devcontainers in action please check out the
[Triton devcontainer vscode demo](https://www.youtube.com/watch?v=ZrCVtV2Bw3s)

To see the vanilla development containers in action please checkout the
[Triton devcontainer demo](https://www.youtube.com/watch?v=kEbN6-pk3sI)

## Why Container-First Development Matters?

Please checkout why container-first development matters [here](./docs/ContainerFirstDevelopment.md)
