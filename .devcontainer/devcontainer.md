# Device Containers Getting Started Guide

This guide walks you through using a
[Development Container](https://containers.dev/)
configured with all the tools needed to build and run Triton (or Triton-CPU).
The setup is optimized for local development using Visual Studio Code.
Full VSCode Dev Container setup details can be found
[official Visual Studio Code documentation](https://code.visualstudio.com/docs/devcontainers/tutorial#_prerequisites).

## Prerequisites

- [VSCode](https://code.visualstudio.com/)
- [VSCode Dev Containers Extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
- A container engine: [Podman](https://podman.io/) (preferred) or
  [Docker](https://docs.docker.com/) (still a work in progress, may not work)
- GPU support (only needed for GPU use):
  - [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
  - [ROCm](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/index.html)
- `jq` (used by setup scripts)

> **GPU users** must install the NVIDIA Container Toolkit/ROCm for GPU support.

> **Root-less triton-profiling container users**: Follow this
> [NVIDIA Development Tools Solution](https://developer.nvidia.com/nvidia-development-tools-solutions-err_nvgpuctrperm-permission-issue-performance-counters)
> to enable access to the NVIDIA GPU performance counters when running ncu.

> **Podman users**: The VSCode Dev Container extension needs the additional settings
> shown below when using podman.
> `docker-compose` or `podman-compose` can be used with podman.
![settings](./gsg/images/settings.png)

---

## Basic Workflow

Below is the basic workflow for developing Triton using VSCode in a Dev Container:

1. Clone Triton Repository: Clone one of the Triton repository and `cd` into the
   top-level of the cloned repository.
2. Bootstrap `triton-dev-containers`: Run the bootstrap command or clone and build
   the Dev Container.
3. Launch VSCode Dev Container: Launch Dev Container from the VSCode command palette.
4. Development: Work as usual, with access to tools and dependencies defined
   in the container.

### Clone Triton Repository

VS Code Device Containers allow development using VS Code, but within a container.
This provide consistent and reproducible development environments for developing
with Triton.
The pre-configured development containers are designed to work with one of:

- `triton`: [https://github.com/triton-lang/triton](https://github.com/triton-lang/triton)
- `triton-amd`: [https://github.com/triton-lang/triton](https://github.com/triton-lang/triton)
- `triton-cpu`: [https://github.com/triton-lang/triton-cpu](https://github.com/triton-lang/triton-cpu)

Clone the repository that is being developed and `cd` into the top-level of the
cloned repository.

### Bootstrap `triton-dev-containers`

This repository is intended to be be cloned under the repository being
developed.
It is recommended to only checkout what is needed for a given development
environment (Sparse Checkout), but it is possible to do a full checkout of this
repository.

The Dev Container Configuration file, `.devcontainer/triton/devcontainer.json`,
is setup with configuration details, like the Docker image to use, extensions to
install, environment variables, etc.
The Dev Container configuration provided supports both root (not recommended)
and non-root (recommended) users.

#### Option 1: Sparse Checkout Script - RECOMMENDED

This option clones only what is needed for a given variant.
Once the script completes, there should be a `.devcontainer/` directory in the
top-level of the repository being developed.

```bash
wget -qO- https://raw.githubusercontent.com/redhat-et/triton-dev-containers/main/.devcontainer/scripts/bootstrap-devcontainer.sh | bash -s triton-cpu
```

> Replace `triton-cpu` (above) with one of the supported variants:
>
> - `triton`
> - `triton-cpu`
> - `triton-amd`

#### Option 2: Clone Everything

This option clones the entire `triton-dev-containers` repository.

```bash
git clone https://github.com/redhat-et/triton-dev-containers.git
cd triton-dev-containers
make devcontainers
```

### Launch VSCode Dev Container

Follow these steps to launch and work with the Dev Container in Visual
Studio Code.

Open the project in Visual Studio Code.
A pop up will appear asking to reopen the project in a Dev Container.

![reopen-in-container](./gsg/images/reopen-in-container.png)

If the pop up doesn't appear, the container can be launched by accessing the
Visual Studio Code Command Palette and looking for the:
`Dev Containers: Reopen in Container` option as shown below.

![reopen-in-container](./gsg/images/rebuild-container.png)

Visual Studio Code will relaunch inside the Dev Container.

When the container is ready the Triton tutorials can be installed as follows
(This step can take a few minutes to complete):

```bash
pip install -e './python[tutorials]'
```

Once the Triton tutorials are installed, they can be run to verify everything is
installed correctly.
If developing with `triton-cpu`, some of the tutorials may not succeed as is.
Run tutorials with `-cpu` in the name, like `02-fused-softmax-cpu.py`
and `03-matrix-multiplication-cpu.py`.

```bash
python python/tutorials/01-vector-add.py
```

## Building Triton with a Custom LLVM in Dev Container

> **_NOTE_**: This setup takes a WHILE to complete

To build Triton with a custom version of LLVM, please enable one of the following
in the `devcontainer.json` file:

```json
"CUSTOM_LLVM": "true"
```

or

```json
"LLVM_TAG": "adba14acea99cc6a17d837763a3248c9d4a2fadf"
```

> Note: if you don't set the LLVM_TAG then the latest tag in `llvm-hash.txt`
file will be used from the relevant Triton project.
