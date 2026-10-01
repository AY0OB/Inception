*This project has been created as part of the 42 curriculum by amairia.*

# Inception

## Description

Inception is a system administration project that deploys a WordPress
website using Docker Compose inside a virtual machine.

The infrastructure contains three services, each built from a custom
Dockerfile using Debian Bookworm:

- NGINX provides HTTPS access using TLS 1.2 and TLS 1.3.
- WordPress with PHP-FPM processes the website's PHP code.
- MariaDB stores the website's database.

NGINX is the only public entry point, on port 443. The services communicate
through a dedicated Docker bridge network.

Two persistent Docker named volumes store the database and WordPress
files. Their data resides under `/home/amairia/data/` inside the VM.

Only the mandatory part is implemented.

## Instructions

### Prerequisites

- A Linux virtual machine with Docker Engine and Docker Compose installed.
- Git, Make and sudo access.
- Internet access for image builds and the first WordPress installation.
- Docker storage configured as described in `DEV_DOC.md`.

### Setup

```bash
git clone https://github.com/AY0OB/Inception.git ~/Inception
cd ~/Inception
cp srcs/.env.example srcs/.env
```

Review the environment settings and create these local secret files,
each containing one non-empty password line:

```text
secrets/db_root_password.txt
secrets/db_password.txt
secrets/wp_admin_password.txt
secrets/wp_user_password.txt
```

Keep the secrets directory private and exclude credentials from Git.
Detailed setup instructions are in `DEV_DOC.md`.

### Build and run

```bash
make
```

Check the services:

```bash
make ps
make logs
```

Stop and remove containers while preserving application data:

```bash
make down
```

### Website access

Configure the host computer's hosts file:

```text
127.0.0.1 amairia.42.fr
```

With VirtualBox NAT, forward host port 443 to guest port 443.

- Website: https://amairia.42.fr
- Administration: https://amairia.42.fr/wp-admin/

The certificate is self-signed, so a browser trust warning is expected.

See `USER_DOC.md` for account information, daily operation and
troubleshooting.

## Project design

### Virtual machines and Docker

A virtual machine runs its own kernel on virtualized hardware.
Containers isolate processes while sharing the Docker host's kernel.

This project uses both: VirtualBox runs a Debian VM, and Docker runs
the application containers inside that VM.

### Secrets and environment variables

Environment variables provide non-secret settings such as the domain,
database name and WordPress usernames.

Docker Compose secrets expose password files only to services that need
them, under `/run/secrets/`. The local source files remain excluded
from Git.

Local Compose secrets are file-based; they are not an encrypted secret
vault. Host file permissions still matter.

During initial configuration, WordPress writes its database credentials
to its persistent `wp-config.php`. Changing a secret file alone does not
change an existing database or WordPress account password.

### Docker network and host network

A Docker bridge network provides a separate network for the containers
and service-name resolution. Ports must be published explicitly for
access through the Docker host.

Host networking shares the host's network namespace and removes that
network isolation.

This project uses a bridge network. WordPress connects to `mariadb:3306`,
and NGINX forwards PHP requests to `wordpress:9000`. Only NGINX publishes
port 443.

### Docker volumes and bind mounts

Docker named volumes are managed by Docker independently of container
lifecycles. Bind mounts expose a specific host path directly inside
a container.

This project uses two native named volumes, without bind-mount driver
options. Docker's `data-root` is configured as:

```text
/home/amairia/data/docker
```

This places persistent volume data beneath the required
`/home/amairia/data/` directory.

NGINX shares the WordPress volume in read-only mode.

### Startup and persistence

Each service has a Dockerfile, configuration and entrypoint script.

- MariaDB initializes its database and application credentials when needed.
- WordPress waits for database access before configuring the website.
- NGINX generates its certificate if absent and validates its configuration.

Entrypoints replace themselves with the service process using `exec`.
The services remain in the foreground and use the `unless-stopped`
restart policy.

Database and website data survive container recreation.
NGINX certificates are regenerated when its container is recreated.

## Repository structure

| Path | Purpose |
| --- | --- |
| `Makefile` | Build and service-management commands |
| `srcs/docker-compose.yml` | Services, network, volumes and secrets |
| `srcs/.env.example` | Non-secret configuration template |
| `srcs/requirements/mariadb/` | MariaDB image, configuration and startup |
| `srcs/requirements/wordpress/` | WordPress/PHP-FPM image and startup |
| `srcs/requirements/nginx/` | NGINX image, HTTPS template and startup |
| `secrets/` | Local password files, ignored by Git |
| `USER_DOC.md` | User and administrator guide |
| `DEV_DOC.md` | Development, deployment and recovery guide |

## Validation performed

- Database authentication.
- WordPress administrator and editor access.
- Persistent data after container recreation.
- HTTPS website response.
- TLS 1.2 and TLS 1.3 accepted.
- TLS 1.0 and TLS 1.1 rejected.
- Automatic service startup and website access after a VM reboot.
- Fresh MariaDB and WordPress initialization in an isolated test project.

Campus migration remains to be verified.

## Resources

- Docker documentation: https://docs.docker.com/
- Docker Engine installation on Debian:
  https://docs.docker.com/engine/install/debian/
- Docker Compose documentation: https://docs.docker.com/compose/
- Docker volumes: https://docs.docker.com/engine/storage/volumes/
- NGINX documentation: https://nginx.org/en/docs/
- PHP-FPM documentation: https://www.php.net/manual/en/install.fpm.php
- MariaDB documentation: https://mariadb.com/docs/
- WP-CLI command reference: https://developer.wordpress.org/cli/commands/
- Community guide consulted: https://github.com/TFHD/Inception

### AI use

An AI assistant was used throughout the project to help plan the work,
explain Docker and service interactions, draft Dockerfiles, configuration
files, entrypoint scripts, Makefile rules and documentation, and propose
tests and troubleshooting steps.

The author applied the changes in the VM and executed the reported tests.
AI-generated suggestions were adjusted based on observed results,
including corrections to WP-CLI cache permissions and password output
during initialization.
