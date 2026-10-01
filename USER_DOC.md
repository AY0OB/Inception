# User documentation

## Services

The website uses three services:

- NGINX receives HTTPS connections and serves static files.
- WordPress with PHP-FPM runs the website.
- MariaDB stores accounts, articles, pages, comments and other database data.

NGINX is the only service publishing an application port on the VM: 443.

## Start and stop

Start the Inception VM in VirtualBox.

Open a terminal inside the VM, or connect from the physical computer:

```bash
ssh -p 2222 amairia@127.0.0.1
```

Run the following commands inside the VM:

```bash
cd ~/Inception
make
```

The first installation requires Internet access and may take several
minutes. Subsequent starts reuse existing data.

Check container status:

```bash
make ps
```

To stop and remove the containers and application network:

```bash
make down
```

This preserves the two persistent volumes. Run `make` to start again.

To shut down the VM cleanly:

```bash
sudo poweroff
```

Containers running before a normal VM reboot restart automatically.
Containers explicitly stopped or removed must be started again.

## Access from inside the VM: campus setup

The VM includes Xfce and Firefox ESR.

In the VirtualBox console, log in as `amairia` and run:

```bash
startxfce4
```

Run this without sudo, from the VM console rather than SSH.
If the graphical desktop is already open, simply launch Firefox.

The VM's `/etc/hosts` must contain:

```text
127.0.0.1 amairia.42.fr
```

Open:

- Website: https://amairia.42.fr
- Administration: https://amairia.42.fr/wp-admin/

The browser connects directly to the VM's port 443.
No hosts-file change on the campus computer is needed.

## Access from Windows: personal setup

To open the website in the physical Windows computer's browser:

1. Configure VirtualBox NAT forwarding from host `127.0.0.1:443`
   to guest port `443`.
2. Open the Windows hosts file with administrator privileges:

```text
C:\Windows\System32\drivers\etc\hosts
```

3. Add:

```text
127.0.0.1 amairia.42.fr
```

4. Open https://amairia.42.fr.

This is a separate access method from the campus VM browser.

## NAT forwarding

| Setup | Purpose | Host IP | Host port | Guest port |
| --- | --- | --- | --- | --- |
| Both | SSH | 127.0.0.1 | 2222 | 22 |
| Personal Windows computer | Browser HTTPS | 127.0.0.1 | 443 | 443 |
| Campus computer | Optional command-line HTTPS test | 127.0.0.1 | 8443 | 443 |

The campus browser runs inside the VM and does not use the 8443 rule.
Opening an external URL on port 8443 is not a complete browsing solution:
WordPress generates links using its configured URL without that port.

## Certificate warning

NGINX uses a self-signed certificate. A browser trust warning is expected.

Verify that you are visiting your local `amairia.42.fr` website, then use
the browser's advanced options to continue.

## Accounts and credentials

Initial WordPress accounts:

| Username | Role | Password file |
| --- | --- | --- |
| amairia | Administrator | `secrets/wp_admin_password.txt` |
| editor | Editor | `secrets/wp_user_password.txt` |

The administrator manages the website and users.
The editor manages content without administrator access.

Database password files:

| File | Purpose |
| --- | --- |
| `secrets/db_password.txt` | Application database user |
| `secrets/db_root_password.txt` | MariaDB root account |

Paths are relative to `~/Inception` inside the VM.
These files remain local and are excluded from Git.

Non-secret settings are in `srcs/.env`.
Their template is `srcs/.env.example`.

To manage WordPress account passwords, use the administrator's Users
section or the account's Profile section. Keep the corresponding local
secret file consistent if it must be reused for a fresh installation.

Changing a secret file alone does not modify an existing account.
Changing the application database password also requires updating
MariaDB and WordPress's database configuration together.

Do not put passwords in commits, screenshots or shared command output.

## Check service health

From the repository root inside the VM:

```bash
make ps
make logs
```

All three containers should be `Up`.
Only NGINX should show a published port mapping.

Press Ctrl+C to stop following logs without stopping the containers.

Test HTTPS from the VM:

```bash
curl -kI --resolve amairia.42.fr:443:127.0.0.1 https://amairia.42.fr
```

Expected response: `HTTP/1.1 200 OK`.

The `-k` option bypasses certificate verification for this local test.

Open the application database client:

```bash
make db-shell
```

Enter the application database password when prompted.

```sql
SHOW TABLES;
EXIT;
```

## Persistent data

Two Docker named volumes preserve the application:

- `srcs_mariadb_data`: database files.
- `srcs_wordpress_data`: WordPress files, configuration and uploads.

Their data is beneath:

```text
/home/amairia/data/docker/volumes/
```

Container replacement and VM reboots preserve these volumes.
Deleting the volumes erases the associated application data.

Do not run `docker compose down -v` on the application unless you
intend to erase its persistent storage.

## Troubleshooting

- SSH connection refused: check that the VM is running, SSH is active
  and the `2222 -> 22` forwarding rule exists.
- Desktop does not start: run `startxfce4` from the VirtualBox console,
  as `amairia`, without sudo.
- Domain not found in the VM browser: check the VM's `/etc/hosts`.
- Website unreachable: check `make ps` and `make logs`.
- HTTP 502: inspect NGINX and WordPress logs; PHP-FPM may not be ready.
- Database connection error: inspect MariaDB logs and check that its
  credentials match WordPress's configuration.
- Container keeps restarting: inspect its startup errors in the logs.
- Certificate warning: expected for the project's self-signed certificate.
