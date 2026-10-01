*This project has been created as part of the 42 curriculum by amairia.*

# Inception

## Description

Inception is a system administration project that deploys a WordPress
website using Docker Compose inside a Debian virtual machine.

The infrastructure contains three services built from custom Dockerfiles:

| Service | Role |
| --- | --- |
| NGINX | HTTPS entry point and static file server |
| WordPress with PHP-FPM | Website application and PHP execution |
| MariaDB | Database storage |

All images use `debian:bookworm` as their base. No prebuilt application
image is used.

NGINX publishes port 443 and accepts TLS 1.2 and TLS 1.3 only.
The services communicate through a dedicated Docker bridge network.

Two native Docker named volumes preserve the database and WordPress
files under `/home/amairia/data/` inside the VM.

The project implements the mandatory part.

## Instructions

### Prerequisites

- A Debian VM with Docker Engine and the Docker Compose plugin.
- Git, Make and sudo privileges inside the VM.
- Internet access for builds and the first WordPress download.
- Docker storage configured as described in [DEV_DOC.md](DEV_DOC.md).

### Initial setup

For a fresh clone:

```bash
git clone https://github.com/AY0OB/Inception.git ~/Inception
cd ~/Inception
cp srcs/.env.example srcs/.env
```

Review `srcs/.env` and create these local password files:

```text
secrets/db_root_password.txt
secrets/db_password.txt
secrets/wp_admin_password.txt
secrets/wp_user_password.txt
```

Each file must contain one non-empty password line.
The secrets directory and the real `.env` file are excluded from Git.

See [DEV_DOC.md](DEV_DOC.md) for complete environment and secret setup.

### Build and run

From the repository root inside the VM:

```bash
make
```

Inspect the services and follow their logs:

```bash
make ps
make logs
```

Stop and remove the containers while retaining their persistent volumes:

```bash
make down
```

### Website access

- Website: https://amairia.42.fr
- Administration: https://amairia.42.fr/wp-admin/

At campus, Firefox ESR runs directly inside the VM.
The VM's `/etc/hosts` contains:

```text
127.0.0.1 amairia.42.fr
```

From the VirtualBox console, log in as `amairia` and launch the desktop:

```bash
startxfce4
```

Run this command without sudo and outside an SSH session.
Open Firefox and visit the website.

This uses the VM's port 443 directly. It does not require administrator
privileges or a hosts-file change on the campus computer.

The certificate is self-signed, so a browser trust warning is expected.

Access from the personal Windows browser is also possible using NAT
forwarding and a Windows hosts entry. Both access methods are documented
in [USER_DOC.md](USER_DOC.md).

## Project description and design choices

### Virtual machines vs Docker

A virtual machine runs its own kernel on virtualized hardware.
Containers isolate processes while sharing the Docker host's kernel,
which generally reduces their startup time and resource overhead.

This project uses both: VirtualBox runs Debian, and Docker runs the
application containers inside Debian. The VM is therefore the Docker host.

### Docker and Docker Compose

A Dockerfile describes how to build an image. A container is a running
instance of an image with its own writable layer.

Compose does not change the nature of an image. It describes how multiple
services are built and run together, including their networks, volumes,
environment variables, secrets and restart policies.

The root Makefile invokes Compose using `srcs/docker-compose.yml`.

### Secrets vs environment variables

Environment variables provide non-secret settings such as the domain,
database name, usernames and email addresses.

Compose secrets expose password files under `/run/secrets/` only to the
services that need them. With local Compose, these are file-based secrets,
not an encrypted secret vault.

WordPress writes its database credentials into its persistent
`wp-config.php`. Changing a secret file alone does not rotate a password
already stored in MariaDB or WordPress.

### Docker network vs host network

A Docker bridge network provides isolated container networking and
service-name resolution. Access from outside requires explicit port
publication.

Host networking shares the Docker host's network namespace.

This project uses a bridge network:

- NGINX sends PHP requests to `wordpress:9000`.
- WordPress connects to `mariadb:3306`.
- Only NGINX publishes a port on the VM: 443.

### Docker volumes vs bind mounts

Named volumes are managed by Docker independently of container
lifecycles. Bind mounts expose a chosen host path inside a container.

This project uses two native named volumes without bind-mount driver
options. Docker's `data-root` is configured as:

```text
/home/amairia/data/docker
```

The volumes are stored beneath this directory. NGINX mounts the
WordPress volume read-only.

### Service initialization

- MariaDB initializes its system tables if needed and executes account
  and database setup through a foreground `mariadbd --bootstrap` process.
  A persistent marker prevents repeating application initialization.
- WordPress waits for database access, downloads its files when absent,
  and creates its configuration and accounts when needed.
- NGINX generates a self-signed certificate when absent, substitutes the
  domain in its configuration template, and validates the configuration.

Each entrypoint finishes with `exec`, making the final service process
PID 1. Services run in the foreground and use `unless-stopped`.

No infinite sleep or tail command is used to keep containers alive.

## Repository structure

| Path | Purpose |
| --- | --- |
| `Makefile` | Build and service-management commands |
| `srcs/docker-compose.yml` | Service and resource definitions |
| `srcs/.env.example` | Non-secret configuration template |
| `srcs/requirements/mariadb/` | MariaDB Dockerfile, configuration and entrypoint |
| `srcs/requirements/wordpress/` | WordPress/PHP-FPM Dockerfile, configuration and entrypoint |
| `srcs/requirements/nginx/` | NGINX Dockerfile, configuration template and entrypoint |
| `secrets/` | Local password files, excluded from Git |
| `USER_DOC.md` | User and administrator instructions |
| `DEV_DOC.md` | Environment setup, implementation and validation procedures |

Application source files are downloaded into the WordPress volume during
initialization. The repository contains the infrastructure code used to
build and configure the services.

## Resources

- [Docker documentation](https://docs.docker.com/)
- [Docker installation on Debian](https://docs.docker.com/engine/install/debian/)
- [Docker Compose](https://docs.docker.com/compose/)
- [Docker volumes](https://docs.docker.com/engine/storage/volumes/)
- [NGINX documentation](https://nginx.org/en/docs/)
- [PHP-FPM documentation](https://www.php.net/manual/en/install.fpm.php)
- [MariaDB documentation](https://mariadb.com/docs/)
- [WP-CLI command reference](https://developer.wordpress.org/cli/commands/)
- [Community guide consulted](https://github.com/TFHD/Inception)

### AI use

An AI assistant helped plan the project, explain the underlying concepts,
draft Dockerfiles, configurations, entrypoint scripts, Makefile rules and
documentation, and propose tests and troubleshooting steps.

The author applied the changes in the VM and checked their behavior.
Suggestions were revised based on observed results, including WP-CLI
cache permissions, initialization output, foreground MariaDB
initialization and browser access inside the campus VM.
