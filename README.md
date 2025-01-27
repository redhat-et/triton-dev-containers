# triton-dev-container

This guide provides step-by-step instructions for using a container
preconfigured with all the tools necessary to build and run Triton.
By mounting the Triton directory from your host into the development
container, you can continue working with your favorite IDE while keeping
all building and running tasks isolated within the container.

## Prerequisites

- **Docker** or **Podman**
- **NVIDIA Container Toolkit for GPU Usage**

> **_NOTE_**: If you are using an NVIDIA GPU, you also need to complete the steps
  to install the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).

> **_NOTE_**: NVIDIA Container Toolkit is not required for `triton-cpu`.

## Building the triton devcontainer

```sh
 make triton-build
```

## Running the triton devcontainer

```sh
 make triton-run [triton_path=<path-to-triton-on-host>]
```

> **_NOTE_**: if you do not provide `triton_path` the triton repo will be cloned
at container startup time.

## Building the triton-cpu devcontainer

```sh
 make triton-cpu-build
```

## Running the triton-cpu devcontainer

```sh
 make triton-cpu-run [triton_path=<path-to-triton-on-host>]
```

> **_NOTE_**: if you do not provide `triton_path` the triton-cpu repo will be cloned
at container startup time.

## Using .devcontainers

Please see the [.devcontainer user guide](./.devcontainer/devcontainer.md)

## A Container First approach to Triton development

The Triton project from OpenAI is at the forefront of a groundbreaking movement
to [democratize AI accelerators and GPU kernel programming](https://next.redhat.com/2024/11/07/democratizing-ai-accelerators-and-gpu-kernel-programming-using-triton/).
By providing a flexible, efficient, and accessible framework for developing
custom GPU kernels, Triton empowers developers to push the boundaries of AI
performance. In this blog, we’ll explore a container-first development
approach that enhances the Triton development workflow. This approach
streamlines the development, testing, and deployment of models, enabling
faster iteration and more efficient model optimization greatly
benefiting the Triton development workflow and improving the Triton
developer experience.

### Why Container-First Development Matters?

AI’s rapid evolution demands cutting-edge development practices to deliver
highly optimised solutions. For teams working on AI models, container-first
development offers a streamlined workflow, enhanced collaboration, and
consistent results across diverse environments. Let’s explore how adopting
this strategy benefits Triton projects.

### What is container first development?

A container-first approach prioritises using containerization technologies
like Docker or Podman throughout the software development lifecycle.
Containers bundle an application with its dependencies, configurations,
and runtime environment into a lightweight, portable unit. This guarantees
consistent behavior across various environments—from a developer’s laptop
to staging servers to production. For Triton, where consistency and
efficiency are paramount, containers are an ideal fit, ensuring
predictable performance with minimal overhead.

### Benefits of Container First Development for Triton

* **Compile Once Run Anywhere**: Containers offer consistency across
environments. This reduces debugging time, enhances confidence in code
quality, and improves CI/CD pipeline reliability.
* **Streamlined Developer Onboarding**: Onboarding new developers can
be challenging due to inconsistent development environments.
Pre-configured container images eliminate this hurdle, enabling
developers to start working immediately without complex setup
processes.
* **Improved Collaboration**: AI projects often involve diverse
teams—data scientists, DevOps engineers, and developers.
Containers act as a common denominator, enabling seamless
collaboration by standardizing tools and libraries within a
single image that can be shared across teams.
* **Enhanced Security**:
  * Containers can use minimal base images, reducing the attack surface.
  * Dockerfiles can generate Software Bills of Materials (SBOMs), helping
    track dependencies and identify vulnerabilities quickly.
  * Security mechanisms like image signing ensure authenticity and
    integrity, reducing risks from malicious images while bolstering trust
    in the software supply chain.

### Triton Container First Development

Currently, Triton development workflows are not fully container-centric.
Developers often begin by cloning the GitHub project and manually
installing all required dependencies on their local machine or
development server. This process can be time-consuming and error-prone,
often resulting in issues such as:

* **Time-Intensive Setup**: Manually configuring environments takes valuable
  time that could be spent on actual development work.
* **System Configuration Disparities**: Differences in local environments can
  introduce subtle bugs that are difficult to reproduce and resolve.
* **Insufficient Documentation**: Incomplete or unclear instructions can slow
  developers down as they troubleshoot setup problems.
* **Dependency Conflicts**

A [pull request](https://github.com/triton-lang/triton/pull/5143) to add a
[Development Container](https://containers.dev/) with all the tools needed to
build and run the Triton project was created in late 2024, it’s hoped that this
will be adopted by the project as it’s a good start towards enabling a
container centric development approach for Triton. This is also being further
developed to support development environments that are not ‘Visual Studio Code’
centric via a github repository and a quay.io image repository to host the
development container images.

### Conclusion

A container-first approach to software development empowers Triton projects with
agility, consistency, and scalability. By isolating dependencies, standardizing
environments, and facilitating seamless collaboration, this approach addresses
many traditional pain points in software development workflows. As the Triton
ecosystem continues to grow and evolve, integrating a container-first mindset
will not only enhance productivity but also ensure that the projects remain
robust, secure, and ready for the future.

### References

* [5 Benefits of a Container-First Approach to Software Development | Docker](https://www.docker.com/blog/5-benefits-of-a-container-first-approach-to-software-development/)