#!/bin/bash
set -euo pipefail

DATA_DIR="/var/lib/mysql"
MARKER="$DATA_DIR/.inception-initialized"

mkdir -p /run/mysqld "$DATA_DIR"
chown -R mysql:mysql /run/mysqld "$DATA_DIR"

if [ ! -f "$MARKER" ]; then
    : "${DB_NAME:?DB_NAME is required}"
    : "${DB_USER:?DB_USER is required}"

    # Restrict identifiers before inserting them into SQL.
    [[ "$DB_NAME" =~ ^[a-zA-Z0-9_]+$ ]]
    [[ "$DB_USER" =~ ^[a-zA-Z0-9_]+$ ]]
    [[ "$DB_USER" != "root" ]]

    DB_PASSWORD="$(cat /run/secrets/db_password)"
    ROOT_PASSWORD="$(cat /run/secrets/db_root_password)"

    # Passwords must be non-empty and written on a single line.
    for password in "$DB_PASSWORD" "$ROOT_PASSWORD"; do
        if [[ -z "$password" || "$password" == *$'\n'* ||
              "$password" == *$'\r'* ]]; then
            echo "Invalid password file: expected one non-empty line." >&2
            exit 1
        fi
    done

    # Escape apostrophes for SQL with NO_BACKSLASH_ESCAPES.
    DB_PASSWORD_SQL="$(printf '%s' "$DB_PASSWORD" | sed "s/'/''/g")"
    ROOT_PASSWORD_SQL="$(printf '%s' "$ROOT_PASSWORD" | sed "s/'/''/g")"

    if [ ! -d "$DATA_DIR/mysql" ]; then
        mariadb-install-db \
            --user=mysql \
            --datadir="$DATA_DIR" \
            --auth-root-authentication-method=socket \
            --skip-test-db
    fi

    # Run initialization SQL in the foreground, then exit.
    echo "Initializing MariaDB database and accounts..."

    gosu mysql mariadbd \
        --bootstrap \
        --datadir="$DATA_DIR" \
        --skip-networking <<SQL
FLUSH PRIVILEGES;
SET SESSION sql_mode = 'NO_BACKSLASH_ESCAPES';
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD_SQL}';
ALTER USER '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD_SQL}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${ROOT_PASSWORD_SQL}');
SQL

    touch "$MARKER"
    chown mysql:mysql "$MARKER"

    unset DB_PASSWORD ROOT_PASSWORD DB_PASSWORD_SQL ROOT_PASSWORD_SQL password
fi

exec gosu mysql "$@"
