# Developer documentation

## Current progress

The virtual machine and Docker environment are ready.
The application services have not been implemented yet.

## Virtual machine

- Hypervisor: VirtualBox 7.0.22
- Operating system: Debian 12 Bookworm, amd64
- Memory: 4096 MB
- CPUs: 2
- Disk: 30 GiB, dynamically allocated VDI
- Network: NAT
- Hostname: Inception
- User: amairia, with sudo privileges
- Installed tasks: SSH server and standard system utilities
- No desktop environment

## SSH access from the host computer

VirtualBox NAT port forwarding:

| Protocol | Host IP | Host port | Guest IP | Guest port |
| --- | --- | --- | --- | --- |
| TCP | 127.0.0.1 | 2222 | Empty | 22 |

Connect from the host computer:

    ssh -p 2222 amairia@127.0.0.1

## Development tools

Installed packages include:

- ca-certificates
- curl
- git
- make
- vim

## Docker installation

Docker was installed from its official Debian APT repository:

https://docs.docker.com/engine/install/debian/

Repository settings:

- URI: https://download.docker.com/linux/debian
- Suite: bookworm
- Component: stable
- Architecture: amd64
- Signing key: /etc/apt/keyrings/docker.asc
- APT source: /etc/apt/sources.list.d/docker.sources

Installed packages:

    sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

Verified versions:

- Docker Engine: 29.8.1
- Docker Compose: v5.5.1

Verification commands:

    sudo docker version
    docker compose version
    systemctl is-active docker

## Docker storage

The file /etc/docker/daemon.json contains:

    {
      "data-root": "/home/amairia/data/docker"
    }

This location was configured before creating application volumes.
Future native Docker named volumes will store their data beneath
/home/amairia/data/docker/volumes.

With the containerd image store, image data may remain under
/var/lib/containerd; data-root still controls Docker volume storage.

Validate and apply the configuration:

    sudo dockerd --validate --config-file=/etc/docker/daemon.json
    sudo systemctl restart docker

Verify the storage location:

    sudo docker info --format '{{.DockerRootDir}}'

Expected result:

    /home/amairia/data/docker

## Sections to complete

- Application configuration and local secrets
- Building and launching with Makefile and Docker Compose
- Managing application containers and volumes
- Persistence checks and data recovery
