# Developer documentation

## Environment

The application runs inside a Debian VM. Docker commands are executed
inside that VM, not on the physical campus computer.

| Setting | Value |
| --- | --- |
| VM name and hostname | Inception |
| VM user | amairia, with sudo privileges |
| Operating system | Debian 12 Bookworm, amd64 |
| RAM | 4096 MB |
| CPUs | 2 |
| Virtual disk capacity | 30 GiB, dynamically allocated |
| Network | VirtualBox NAT |
| Personal VirtualBox version | 7.0.22 |
| Campus VirtualBox version | 7.0.26 |
| Desktop inside VM | Xfce |
| Browser inside VM | Firefox ESR |

Recorded Docker versions:

- Docker Engine: 29.8.1
- Docker Compose: v5.5.1

These are recorded environment versions, not package-version pins.

## Fresh VM setup

Install Debian with SSH server and standard system utilities.
Create the `amairia` user with sudo privileges.

Install development tools:

```bash
sudo apt update
sudo apt install -y ca-certificates curl git make vim
```

For browser access directly inside the VM:

```bash
sudo apt install --no-install-recommends xorg xinit xfce4 dbus-x11 firefox-esr
```

From the VirtualBox console, as the normal user:

```bash
startxfce4
```

Do not run this command through SSH or with sudo.

Add this entry to `/etc/hosts` inside the VM:

```text
127.0.0.1 amairia.42.fr
```

Retain the existing hosts entries.

## Docker installation

Use the official Debian installation instructions:

https://docs.docker.com/engine/install/debian/

On a fresh Debian Bookworm VM, configure the repository:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg \
    -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: bookworm
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
```

Verify:

```bash
sudo docker version
docker compose version
systemctl is-active docker
```

## Configure storage before creating volumes

Create the directories:

```bash
sudo mkdir -p /home/amairia/data/docker /etc/docker
```

Set `/etc/docker/daemon.json` to:

```json
{
  "data-root": "/home/amairia/data/docker"
}
```

If this file already contains settings, retain them when adding
`data-root`.

Validate and apply:

```bash
sudo dockerd --validate --config-file=/etc/docker/daemon.json
sudo systemctl restart docker
sudo docker info --format '{{.DockerRootDir}}'
```

Expected result:

```text
/home/amairia/data/docker
```

Changing `data-root` does not automatically move existing Docker data.
Configure it before the first application launch on a fresh VM.

Containerd image storage may remain under `/var/lib/containerd`.
The named volumes use Docker's configured data directory.

## Repository and configuration

For a fresh installation:

```bash
git clone https://github.com/AY0OB/Inception.git ~/Inception
cd ~/Inception
cp srcs/.env.example srcs/.env
```

Do not overwrite an existing `.env` when resuming an installation.

Configuration variables:

| Variable | Purpose |
| --- | --- |
| DOMAIN_NAME | Website domain |
| DB_NAME | WordPress database name |
| DB_USER | Application database user |
| WP_TITLE | Website title |
| WP_ADMIN_USER | Administrator username |
| WP_ADMIN_EMAIL | Administrator email |
| WP_USER | Second WordPress username |
| WP_USER_EMAIL | Second WordPress email |

The configured domain is `amairia.42.fr`.
The administrator username must not contain `admin`, ignoring case.
The two WordPress usernames must differ.

Create the local secret files:

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

Use an editor to put one non-empty password line in each file:

```bash
vim secrets/db_root_password.txt
vim secrets/db_password.txt
vim secrets/wp_admin_password.txt
vim secrets/wp_user_password.txt
chmod 600 secrets/*.txt
```

Verify Git exclusions:

```bash
git check-ignore srcs/.env secrets/db_password.txt
```

MariaDB receives the root and application database secrets.
WordPress receives the application database secret and its two account
secrets. NGINX receives none of these password files.

## Build and service management

Run commands from `~/Inception`.

Validate Compose:

```bash
sudo docker compose --env-file srcs/.env -f srcs/docker-compose.yml config -q
```

Build and launch:

```bash
make
```

| Command | Action |
| --- | --- |
| `make` or `make up` | Build images and start services |
| `make down` | Remove containers and network, retain volumes |
| `make ps` | Show container status |
| `make logs` | Follow recent service logs |
| `make db-shell` | Open the application database client |

The Makefile calls Compose with `srcs/.env` and
`srcs/docker-compose.yml`.

Internet access is required for Debian packages, WP-CLI and the initial
WordPress download. WP-CLI and WordPress downloads are not version-pinned;
fresh builds or installations can retrieve newer releases.

Images are named after their services:

- `mariadb:inception`
- `wordpress:inception`
- `nginx:inception`

After editing a Dockerfile or a file copied into an image, run `make up`
to rebuild and apply the change.

## Common structure and service differences

Each service contains:

- A Dockerfile defining the image.
- A `conf/` directory containing configuration.
- A `tools/entrypoint.sh` script preparing runtime state.

Compose defines the environment, secrets, network, volumes and restart
policy for each service.

| Service | Configuration | Final process |
| --- | --- | --- |
| MariaDB | `50-server.cnf` | `mariadbd` |
| WordPress | `www.conf` | `php-fpm8.2 -F` |
| NGINX | `default.conf.template` | `nginx -g "daemon off;"` |

### MariaDB

The script prepares directory ownership and checks the persistent marker:

```text
/var/lib/mysql/.inception-initialized
```

When the marker is absent:

1. Validate database identifiers and read the secrets.
2. Initialize system tables with `mariadb-install-db` if absent.
3. Execute application setup SQL using `mariadbd --bootstrap`
   synchronously in the foreground, with networking disabled.
4. Create the marker only after successful initialization.

Finally, `exec gosu mysql "$@"` starts the database server as PID 1
under the `mysql` user.

The bootstrap process terminates before the final server starts.
There is no background server, infinite loop or keep-alive workaround.

Local root authentication through the Unix socket is retained alongside
the configured root password.

### WordPress and PHP-FPM

The script validates settings, reads secrets and prepares file ownership.
WP-CLI runs under `www-data`.

A bounded connection loop waits for MariaDB. It then:

1. Downloads WordPress when its files are absent.
2. Creates `wp-config.php` when absent.
3. Installs the database tables and administrator if not installed.
4. Creates the second account as an editor if absent.
5. Replaces the shell with foreground PHP-FPM.

Initialization commands receiving passwords have their standard output
suppressed to avoid echoing credentials into Docker logs.

Existing website data and passwords are not reset on restart.

### NGINX

The script creates a self-signed certificate when its files are absent.
It substitutes only `DOMAIN_NAME` in the configuration template,
preserving NGINX variables such as `$uri`.

After `nginx -t` succeeds, it replaces the shell with foreground NGINX.

The certificate is stored in the container's writable layer. It survives
a restart but is regenerated when the container is recreated.

## Networking

The VM is the Docker host. The physical computer is the VirtualBox host.

The Compose bridge network is named `inception`; its actual Docker name
is normally `srcs_inception`.

Request flow:

1. Browser to NGINX: HTTPS on port 443.
2. NGINX to WordPress: FastCGI at `wordpress:9000`.
3. WordPress to MariaDB: database connection at `mariadb:3306`.

NGINX also reads static files from the WordPress volume.

Only NGINX publishes an application port on the VM.
An `EXPOSE` instruction alone does not publish a host port.

`depends_on` controls creation/startup order, not readiness.
WordPress performs its own database-readiness check.

All services use `restart: unless-stopped`. This applies to unexpected
exits and services previously running when Docker restarts. Explicitly
stopped containers remain stopped.

## Browser and SSH access

### Campus

Use Firefox inside the VM with this VM hosts entry:

```text
127.0.0.1 amairia.42.fr
```

Open https://amairia.42.fr after starting Xfce from the VirtualBox console.

This avoids any need to edit the physical campus computer's hosts file
or bind its privileged port 443.

### Personal Windows computer

To use the Windows browser, configure the same domain entry in:

```text
C:\Windows\System32\drivers\etc\hosts
```

Forward the physical computer's port 443 to the VM's port 443.

### NAT rules

| Setup | Purpose | Host IP | Host port | Guest port |
| --- | --- | --- | --- | --- |
| Both | SSH | 127.0.0.1 | 2222 | 22 |
| Windows | Browser HTTPS | 127.0.0.1 | 443 | 443 |
| Campus | Optional HTTPS diagnostic | 127.0.0.1 | 8443 | 443 |

Leave the guest IP empty in these NAT rules.

From the physical computer:

```bash
ssh -p 2222 amairia@127.0.0.1
```

Optional campus forwarding test, outside SSH:

```bash
curl -kI --resolve amairia.42.fr:8443:127.0.0.1 \
    https://amairia.42.fr:8443
```

This tests forwarding only. WordPress still generates links for its
canonical URL, `https://amairia.42.fr`, without port 8443.

## Persistent storage

| Volume | Container path | Consumers |
| --- | --- | --- |
| `srcs_mariadb_data` | `/var/lib/mysql` | MariaDB |
| `srcs_wordpress_data` | `/var/www/html` | WordPress and NGINX |

NGINX mounts the WordPress volume read-only.
Both volumes are native Docker named volumes, without bind-mount driver
options.

Inspect storage:

```bash
sudo docker volume ls
sudo docker volume inspect srcs_mariadb_data srcs_wordpress_data \
    --format '{{.Name}} : {{.Mountpoint}}'
```

Expected paths:

```text
/home/amairia/data/docker/volumes/srcs_mariadb_data/_data
/home/amairia/data/docker/volumes/srcs_wordpress_data/_data
```

The `srcs` project prefix derives from the Compose file's directory.
Keep the same project name to reuse these volumes.

Removing a container does not delete its named volumes.
Using `down -v` deletes the project's volumes and their data.

## Validation procedures

These commands and checks describe how to validate the deployment.

### HTTPS and HTTP

Inside the VM:

```bash
curl -kI --resolve amairia.42.fr:443:127.0.0.1 https://amairia.42.fr
curl -I --max-time 5 --resolve amairia.42.fr:80:127.0.0.1 http://amairia.42.fr
```

HTTPS should return `200 OK`. The HTTP connection should fail because
the project does not publish or serve port 80.

### TLS versions

TLS 1.2 and TLS 1.3 should succeed:

```bash
curl -kI --tlsv1.2 --tls-max 1.2 \
    --resolve amairia.42.fr:443:127.0.0.1 https://amairia.42.fr

curl -kI --tlsv1.3 --tls-max 1.3 \
    --resolve amairia.42.fr:443:127.0.0.1 https://amairia.42.fr
```

TLS 1.0 and TLS 1.1 should receive a protocol-version alert:

```bash
openssl s_client -connect 127.0.0.1:443 \
    -servername amairia.42.fr -tls1 \
    -cipher 'DEFAULT:@SECLEVEL=0' -brief </dev/null

openssl s_client -connect 127.0.0.1:443 \
    -servername amairia.42.fr -tls1_1 \
    -cipher 'DEFAULT:@SECLEVEL=0' -brief </dev/null
```

The reduced security level applies only to these test clients.

### Database and accounts

```bash
make db-shell
```

Then:

```sql
SELECT DATABASE(), CURRENT_USER();
SHOW TABLES;
EXIT;
```

The database should contain the WordPress tables.

Log into WordPress with both accounts. The administrator can manage
users; the editor can manage content without access to user management.

### Persistence and restart

1. Add a comment using the editor account.
2. Edit a page using the administrator account.
3. Confirm both changes on the public website.
4. Reboot the VM with `sudo reboot`.
5. Check `make ps` and website access.
6. Confirm the page and comment remain present.

To test container replacement separately, use Compose's
`up -d --force-recreate`, retaining the same project name and volumes.
Allow services to become ready before checking the website.

### Configuration changes

For a PHP-FPM port-change exercise, update all matching references:

- `listen` in WordPress's `conf/www.conf`.
- `fastcgi_pass` in NGINX's configuration template.
- The WordPress Dockerfile's `EXPOSE` declaration for consistency.

Run `make up`, then verify HTTPS access. Restore the required final
configuration after the exercise.

## Credential management

Secret files are initialization inputs, not automatic password-rotation
mechanisms.

Changing the application database password requires coordinating:

- The MariaDB application account.
- `secrets/db_password.txt`.
- WordPress's persistent `wp-config.php`.

WordPress account passwords are managed in WordPress. Update local
initialization secrets consistently when appropriate.

Keep secret files, data backups and VM exports outside Git.

## Backup, migration and recovery

Git preserves infrastructure source code and documentation, not the
live database, uploads, `.env` or local secrets.

For a complete VM checkpoint:

1. Shut down cleanly using `sudo poweroff`.
2. Export the powered-off VM from VirtualBox as an OVA appliance.
3. Store the export privately outside the repository.
4. Import the appliance on the destination computer.
5. Check storage space, RAM, CPUs and NAT forwarding rules.
6. Start the VM and verify Docker services and website access.

On the campus Linux host, use port 8443 rather than privileged host
port 443 for the optional HTTPS forwarding rule. Use the browser inside
the VM for normal website access.

An export contains the VM's secrets and data as they existed when it was
created. Changes made after that export require a new backup.

To recover a checkpoint, import the saved appliance and repeat the
service and access checks.

Cloning the source repository alone does not restore a website backup.
Without the original volumes, the application creates a fresh website.

## Git synchronization

The development repository uses `origin` for GitHub.
A campus checkout can additionally use `school` for the assigned
42 repository.

With a clean checkout, after verifying both remote URLs:

```bash
git switch main
git pull --ff-only origin main
git push school main
```

If the school repository expects another submission branch, use the
branch required by the assignment.

A normal push preserves commit identifiers and dates.
Do not force-push to resolve an unexpected divergence; inspect it first.
