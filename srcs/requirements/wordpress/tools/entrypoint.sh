#!/bin/bash
set -euo pipefail

cd /var/www/html

: "${DB_NAME:?DB_NAME is required}"
: "${DB_USER:?DB_USER is required}"
: "${DOMAIN_NAME:?DOMAIN_NAME is required}"
: "${WP_TITLE:?WP_TITLE is required}"
: "${WP_ADMIN_USER:?WP_ADMIN_USER is required}"
: "${WP_ADMIN_EMAIL:?WP_ADMIN_EMAIL is required}"
: "${WP_USER:?WP_USER is required}"
: "${WP_USER_EMAIL:?WP_USER_EMAIL is required}"

read_secret() {
    local value
    value="$(cat "$1")"

    if [[ -z "$value" || "$value" == *$'\n'* ||
          "$value" == *$'\r'* ]]; then
        echo "Invalid secret file: $1" >&2
        return 1
    fi

    printf '%s' "$value"
}

DB_PASSWORD="$(read_secret /run/secrets/db_password)"
WP_ADMIN_PASSWORD="$(read_secret /run/secrets/wp_admin_password)"
WP_USER_PASSWORD="$(read_secret /run/secrets/wp_user_password)"

if [[ "${WP_ADMIN_USER,,}" == *admin* ]]; then
    echo "The administrator username must not contain 'admin'." >&2
    exit 1
fi

if [[ "${WP_ADMIN_USER,,}" == "${WP_USER,,}" ]]; then
    echo "WordPress users must have different usernames." >&2
    exit 1
fi

mkdir -p /run/php
chown -R www-data:www-data /var/www/html

wp_cmd() {
    gosu www-data wp \
        --path=/var/www/html \
        --url="https://${DOMAIN_NAME}" \
        "$@"
}

echo "Waiting for MariaDB..."

db_ready=0

for attempt in {1..30}; do
    if MYSQL_PWD="$DB_PASSWORD" mariadb \
        --protocol=TCP \
        --host=mariadb \
        --port=3306 \
        --user="$DB_USER" \
        --database="$DB_NAME" \
        --connect-timeout=2 \
        --execute="SELECT 1;" >/dev/null 2>&1; then
        db_ready=1
        break
    fi

    sleep 2
done

if [ "$db_ready" -ne 1 ]; then
    echo "Cannot connect to MariaDB after 30 attempts." >&2
    exit 1
fi

echo "MariaDB is ready."

if [ ! -f wp-includes/version.php ]; then
    echo "Downloading WordPress..."
    wp_cmd core download
fi

if [ ! -f wp-config.php ]; then
    echo "Creating WordPress configuration..."

    wp_cmd config create \
        --dbname="$DB_NAME" \
        --dbuser="$DB_USER" \
        --dbhost="mariadb:3306" \
        --dbcharset="utf8mb4" \
        --prompt=dbpass <<< "$DB_PASSWORD" >/dev/null
fi

chmod 640 wp-config.php

if ! wp_cmd core is-installed; then
    echo "Installing WordPress..."

    wp_cmd core install \
        --url="https://${DOMAIN_NAME}" \
        --title="$WP_TITLE" \
        --admin_user="$WP_ADMIN_USER" \
        --admin_email="$WP_ADMIN_EMAIL" \
        --skip-email \
        --prompt=admin_password <<< "$WP_ADMIN_PASSWORD" >/dev/null
fi

if ! wp_cmd user get "$WP_USER" --field=ID >/dev/null 2>&1; then
    echo "Creating the second WordPress user..."

    wp_cmd user create "$WP_USER" "$WP_USER_EMAIL" \
        --role=editor \
        --prompt=user_pass <<< "$WP_USER_PASSWORD" >/dev/null
fi

unset DB_PASSWORD WP_ADMIN_PASSWORD WP_USER_PASSWORD

echo "Starting PHP-FPM..."
exec "$@"
