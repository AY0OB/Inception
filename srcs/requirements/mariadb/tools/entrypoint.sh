#!/bin/bash
set -euo pipefail

DATA_DIR="/var/lib/mysql"
SOCKET="/run/mysqld/mysqld.sock"
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

    # Temporary server: local socket only, no TCP connections.
    gosu mysql mariadbd --skip-networking --socket="$SOCKET" &
    TEMP_PID=$!

    cleanup() {
        kill -TERM "$TEMP_PID" 2>/dev/null || true
        wait "$TEMP_PID" 2>/dev/null || true
    }

    trap cleanup EXIT
    trap 'exit 143' TERM
    trap 'exit 130' INT

    ready=0
    for attempt in {1..30}; do
        if mariadb --protocol=socket --socket="$SOCKET" \
            -u root -e "SELECT 1" >/dev/null 2>&1; then
            ready=1
            break
        fi

        if ! kill -0 "$TEMP_PID" 2>/dev/null; then
            echo "MariaDB initialization server stopped unexpectedly." >&2
            exit 1
        fi

        sleep 1
    done

    if [ "$ready" -ne 1 ]; then
        echo "MariaDB did not become ready in time." >&2
        exit 1
    fi

    mariadb --protocol=socket --socket="$SOCKET" -u root <<SQL
SET SESSION sql_mode = 'NO_BACKSLASH_ESCAPES';
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'%'
    IDENTIFIED BY '${DB_PASSWORD_SQL}';
ALTER USER '${DB_USER}'@'%'
    IDENTIFIED BY '${DB_PASSWORD_SQL}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${ROOT_PASSWORD_SQL}');
SQL

    kill -TERM "$TEMP_PID"
    wait "$TEMP_PID"
    trap - EXIT TERM INT

    touch "$MARKER"
    chown mysql:mysql "$MARKER"
fi

exec gosu mysql "$@"
