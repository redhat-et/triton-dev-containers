# triton-dev-container

This guide provides step-by-step instructions for using a container
preconfigured with all the tools necessary to build and run Triton.
By mounting the Triton directory from your host into the development
container, you can continue working with your favorite IDE while keeping
all building and running tasks isolated within the container.

## Prerequisites

* **Docker** or **Podman**
* **NVIDIA Container Toolkit for GPU Usage**

> **_NOTE_**: If you are using an NVIDIA GPU, you also need to complete the steps
  to install the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).

> **_NOTE_**: NVIDIA Container Toolkit is not required for `triton-cpu`.

## Building the triton devcontainer

```sh
 make triton-build
```

## Running the triton devcontainer

```sh
 make triton-run triton_path=<path-to-triton-on-host>
```

## Building the triton-cpu devcontainer

```sh
 make triton-cpu-build
```

## Running the triton-cpu  devcontainer

```sh
 make triton-cpu-run triton_path=<path-to-triton-cpu-on-host>
```

## Using .devcontainers

Please see the [.devcontainer user guide](./.devcontainer/devcontainer.md)