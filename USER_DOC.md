# User documentation

## Services

The project provides a WordPress website through three services:

- NGINX: receives HTTPS connections on port 443 and serves static files.
- WordPress with PHP-FPM: runs the website's PHP code.
- MariaDB: stores the website's database, including accounts and content.

Only NGINX publishes a port on the virtual machine.

## Start and stop the project

Start the virtual machine and connect from the host computer:

```bash
ssh -p 2222 amairia@127.0.0.1
```

From the project directory:

```bash
cd ~/Inception
make
```

This builds the images and starts the services in the background.
The first installation requires Internet access and may take a few minutes.

To stop and remove the application containers and network:

```bash
make down
```

The named volumes and their data are preserved.
Run `make` to start the application again.

To shut down the virtual machine:

```bash
sudo poweroff
```

Running containers use the `unless-stopped` restart policy and restart
automatically after a VM reboot. Containers explicitly stopped or removed
must be started again.

## Access the website

VirtualBox uses NAT with these forwarding rules:

| Purpose | Host IP | Host port | Guest port |
| --- | --- | --- | --- |
| SSH | 127.0.0.1 | 2222 | 22 |
| HTTPS | 127.0.0.1 | 443 | 443 |

On the computer running the browser, add this entry to the hosts file:

```text
127.0.0.1 amairia.42.fr
```

Hosts file locations:

- Windows: `C:\Windows\System32\drivers\etc\hosts`
- Linux: `/etc/hosts`

Editing this file requires administrator privileges.
This host configuration is separate from the VM and must be checked
again when moving to another computer.

Website: https://amairia.42.fr

Administration: https://amairia.42.fr/wp-admin/

The project uses a self-signed certificate. A browser certificate warning
is expected. Verify that you are opening your local project domain before
continuing.

## Accounts and credentials

The initial WordPress accounts are:

| Username | Role | Password file |
| --- | --- | --- |
| amairia | Administrator | `secrets/wp_admin_password.txt` |
| editor | Editor | `secrets/wp_user_password.txt` |

The administrator manages the website and users.
The editor manages content without administrator access.

Database credentials are separate:

- `secrets/db_password.txt`: password for the application's database user.
- `secrets/db_root_password.txt`: password for the MariaDB root account.

All paths above are relative to the project directory.
Secrets remain local and are excluded from Git.

Non-secret settings are in `srcs/.env`.
The tracked `srcs/.env.example` documents the expected settings.

Changing a secret file alone does not update an existing account password.
Credential changes must be coordinated with the database, WordPress and
its configuration.

## Check service health

List the containers:

```bash
make ps
```

All three services should be `Up`. Only NGINX should publish port 443.

Follow the logs:

```bash
make logs
```

Press Ctrl+C to leave the log display without stopping the containers.

Test the website from inside the VM:

```bash
curl -kI --resolve amairia.42.fr:443:127.0.0.1 https://amairia.42.fr
```

The expected response is `HTTP/1.1 200 OK`.
The `-k` option bypasses certificate verification for this local test.

To open the database client while MariaDB is running:

```bash
make db-shell
```

Enter the application database password when prompted.
Type `EXIT;` to leave the client.

## Persistent data

Two Docker named volumes store application data:

- `srcs_mariadb_data`: database files.
- `srcs_wordpress_data`: WordPress files, configuration and uploads.

Their data is stored under:

```text
/home/amairia/data/docker/volumes/
```

Data survives container replacement and VM reboots.
Do not delete these volumes or use `docker compose down -v` on the
application unless you intend to erase its persistent data.

## Troubleshooting

- SSH connection refused: check that the VM is running and the SSH
  forwarding rule is configured.
- Website unreachable: check the hosts entry, HTTPS forwarding rule
  and `make ps`.
- HTTP 502: inspect the WordPress and NGINX logs; PHP-FPM may still be
  starting or may have failed.
- Database connection error: inspect MariaDB logs and check that the
  stored database credentials match the application configuration.
- Restarting container: inspect `make logs` to identify the startup error.
