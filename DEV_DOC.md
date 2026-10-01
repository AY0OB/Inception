# Developer documentation

## Project status

The three mandatory services are implemented:

- MariaDB
- WordPress with PHP-FPM
- NGINX with HTTPS

Verified behavior:

- WordPress installation and administrator/editor login.
- Database and website-file persistence after container recreation.
- TLS 1.2 and TLS 1.3 accepted; TLS 1.0 and TLS 1.1 rejected.
- Automatic service restart after a VM reboot.
- Successful HTTPS response after reboot.
- Fresh MariaDB and WordPress installation in an isolated Compose project.

Campus migration and school-repository synchronization remain to be tested.

## Virtual machine

| Setting | Value |
| --- | --- |
| Hypervisor | VirtualBox 7.0.22 |
| Operating system | Debian 12 Bookworm, amd64 |
| Memory | 4096 MB |
| CPUs | 2 |
| Disk | 30 GiB, dynamically allocated VDI |
| Network | NAT |
| Hostname | Inception |
| User | amairia, with sudo privileges |
| Installed tasks | SSH server and standard system utilities |

No desktop environment is installed.

VirtualBox NAT forwarding:

| Purpose | Host IP | Host port | Guest IP | Guest port |
| --- | --- | --- | --- | --- |
| SSH | 127.0.0.1 | 2222 | Empty | 22 |
| HTTPS | 127.0.0.1 | 443 | Empty | 443 |

Connect from the host computer:

```bash
ssh -p 2222 amairia@127.0.0.1
```

## Development prerequisites

Install the development tools inside the VM:

```bash
sudo apt update
sudo apt install -y ca-certificates curl git make vim
```

Docker was installed using the official Debian instructions:

https://docs.docker.com/engine/install/debian/

Repository settings:

- URI: https://download.docker.com/linux/debian
- Suite: bookworm
- Component: stable
- Architecture: amd64
- Signing key: /etc/apt/keyrings/docker.asc
- APT source: /etc/apt/sources.list.d/docker.sources

Packages installed after configuring the repository:

```bash
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Versions recorded during setup:

- Docker Engine: 29.8.1
- Docker Compose: v5.5.1

Verify the installation:

```bash
sudo docker version
docker compose version
systemctl is-active docker
```

## Docker storage configuration

Before creating application volumes on a fresh VM, create the data directory:

```bash
sudo mkdir -p /home/amairia/data/docker
sudo mkdir -p /etc/docker
```

Configure `/etc/docker/daemon.json`:

```json
{
  "data-root": "/home/amairia/data/docker"
}
```

If the file already contains other daemon settings, retain them.

Validate and apply:

```bash
sudo dockerd --validate --config-file=/etc/docker/daemon.json
sudo systemctl restart docker
sudo docker info --format '{{.DockerRootDir}}'
```

Expected Docker root directory:

```text
/home/amairia/data/docker
```

Changing `data-root` does not migrate existing Docker data automatically.
This project configured the location before creating its volumes.

With the containerd image store, image data may remain under
`/var/lib/containerd`. Docker named volumes use the configured Docker
data directory.

## Repository setup

Clone into the VM user's home:

```bash
git clone https://github.com/AY0OB/Inception.git ~/Inception
cd ~/Inception
cp srcs/.env.example srcs/.env
```

Review `srcs/.env` before the first launch. It contains:

- Domain name.
- Database name and application user.
- Website title.
- WordPress usernames and email addresses.

The administrator username must not contain `admin`, regardless of case.
The two WordPress usernames must differ.

Create the local secrets directory and password files:

```bash
install -d -m 700 secrets
(
    umask 077
    touch secrets/db_root_password.txt \
          secrets/db_password.txt \
          secrets/wp_admin_password.txt \
          secrets/wp_user_password.txt
)
```

Use an editor to put one non-empty password line in each file, then apply:

```bash
chmod 600 secrets/*.txt
```

Do not commit these files or `srcs/.env`.

Verify ignore rules:

```bash
git check-ignore srcs/.env secrets/db_password.txt
```

The same database password secret is supplied to MariaDB and WordPress.
WordPress does not receive the MariaDB root password.

## Build and launch

Run all project commands from `~/Inception`.

Validate Compose:

```bash
sudo docker compose --env-file srcs/.env -f srcs/docker-compose.yml config -q
```

Build and start:

```bash
make
```

The Makefile runs Compose, which builds each service from its Dockerfile.

Internet access is required for Debian packages, WP-CLI and the initial
WordPress download.

The base image is `debian:bookworm`. Application images are:

- `mariadb:inception`
- `wordpress:inception`
- `nginx:inception`

WP-CLI and WordPress downloads are not currently pinned to specific
versions, so a future fresh installation may retrieve newer releases.

## Shared service structure

Each service has the same repository structure but a different role:

| File | Purpose |
| --- | --- |
| `Dockerfile` | Install dependencies and prepare the image |
| `conf/` | Store service configuration or configuration templates |
| `tools/entrypoint.sh` | Prepare the service at container startup |
| `srcs/docker-compose.yml` | Define service relationships and resources |

| Service | Configuration | Startup work | Main process |
| --- | --- | --- | --- |
| MariaDB | `50-server.cnf` | Initialize database and credentials if needed | `mariadbd` |
| WordPress | `www.conf` | Wait for MariaDB, install/configure WordPress and accounts if absent | `php-fpm8.2 -F` |
| NGINX | `default.conf.template` | Generate certificate if absent, substitute domain, validate configuration | `nginx -g "daemon off;"` |

Entrypoint scripts finish with `exec`, so the service becomes PID 1.
No infinite sleep or tail command is used to keep containers running.

MariaDB and WordPress initialize persistent data only when needed.
Editing an initialization secret does not rotate an existing account's
password.

## Networking and request flow

The services share the Compose bridge network `inception`.
With the current project directory, its Docker name is `srcs_inception`.

NGINX is the only service publishing a host port: 443.

- The browser connects to NGINX over HTTPS.
- NGINX serves static files from the shared WordPress volume.
- PHP requests are forwarded to `wordpress:9000` using FastCGI.
- WordPress connects to `mariadb:3306` for database access.

Service names are resolved through Docker networking.

`depends_on` controls startup order, not application readiness.
The WordPress entrypoint performs a bounded database-connection check
before continuing.

## Website access from the host computer

Add the following entry to the host computer's hosts file:

```text
127.0.0.1 amairia.42.fr
```

Locations:

- Windows: `C:\Windows\System32\drivers\etc\hosts`
- Linux: `/etc/hosts`

Administrator privileges are required.
The hosts entry and VirtualBox forwarding rules must be checked when
moving to another computer.

NGINX generates a self-signed certificate for `DOMAIN_NAME`.
A browser trust warning is expected.

Certificate files are stored in the NGINX container, not in Git.
They survive a container restart but are regenerated after container
recreation.

## Managing services

| Command | Action |
| --- | --- |
| `make` or `make up` | Build images and start services |
| `make down` | Remove application containers and network, retain volumes |
| `make ps` | Show container status |
| `make logs` | Follow recent service logs |
| `make db-shell` | Open the application database client |

Press Ctrl+C to leave log following without stopping services.

After changing a Dockerfile, copied configuration or entrypoint, run
`make up` to rebuild and apply the changes.

The `unless-stopped` restart policy restarts crashed containers and
running services after a Docker/VM restart. Explicitly stopped services
remain stopped until started again.

## Persistent volumes

| Volume | Container path | Used by |
| --- | --- | --- |
| `srcs_mariadb_data` | `/var/lib/mysql` | MariaDB |
| `srcs_wordpress_data` | `/var/www/html` | WordPress and NGINX |

NGINX mounts the WordPress volume read-only.

These are native Docker named volumes, without bind-mount driver options.

Inspect their host locations:

```bash
sudo docker volume inspect srcs_mariadb_data srcs_wordpress_data \
    --format '{{.Name}} : {{.Mountpoint}}'
```

Recorded locations:

```text
/home/amairia/data/docker/volumes/srcs_mariadb_data/_data
/home/amairia/data/docker/volumes/srcs_wordpress_data/_data
```

Compose derives the `srcs` prefix from the directory containing the
Compose file. Changing the Compose project name creates a separate set
of resources.

## Validation

Inspect status and logs:

```bash
make ps
make logs
```

Test HTTPS from the VM:

```bash
curl -kI --resolve amairia.42.fr:443:127.0.0.1 https://amairia.42.fr
```

Test accepted protocols:

```bash
curl -kI --tlsv1.2 --tls-max 1.2 \
    --resolve amairia.42.fr:443:127.0.0.1 https://amairia.42.fr

curl -kI --tlsv1.3 --tls-max 1.3 \
    --resolve amairia.42.fr:443:127.0.0.1 https://amairia.42.fr
```

Test rejected protocols:

```bash
openssl s_client -connect 127.0.0.1:443 \
    -servername amairia.42.fr -tls1 \
    -cipher 'DEFAULT:@SECLEVEL=0' -brief </dev/null

openssl s_client -connect 127.0.0.1:443 \
    -servername amairia.42.fr -tls1_1 \
    -cipher 'DEFAULT:@SECLEVEL=0' -brief </dev/null
```

The old-protocol tests should receive a protocol-version alert.

Persistence was tested by creating a database value and a file, recreating
the relevant container without deleting volumes, and reading the same
data again.

Automatic startup was tested by rebooting the VM and checking the website
without running `make up`.

## Backup and recovery

Git stores source files and documentation. It does not store the database,
uploads, local configuration or secrets.

For a complete portable checkpoint:

1. Shut down the VM cleanly with `sudo poweroff`.
2. Use VirtualBox to export the powered-off VM as an appliance.
3. Keep the export outside the Git repository.
4. Import it on the destination computer.
5. Verify networking, forwarding rules and the host's hosts entry.
6. Start the VM and verify containers and website access.

The export contains local secrets and application data; keep it private.
The imported disk must retain sufficient available space.

For recovery from this checkpoint, import the saved appliance and repeat
the access and service checks. Changes made after the export will not
exist in that checkpoint.

A source-only clone is not a backup of the existing website: without its
volumes, it creates a new installation using the supplied configuration.
