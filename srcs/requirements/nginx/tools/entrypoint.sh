#!/bin/bash
set -euo pipefail

: "${DOMAIN_NAME:?DOMAIN_NAME is required}"

mkdir -p /etc/nginx/ssl

if [ ! -s /etc/nginx/ssl/inception.crt ] ||
   [ ! -s /etc/nginx/ssl/inception.key ]; then
    echo "Generating TLS certificate..."

    openssl req -x509 -nodes -newkey rsa:2048 \
        -days 365 \
        -keyout /etc/nginx/ssl/inception.key \
        -out /etc/nginx/ssl/inception.crt \
        -subj "/CN=${DOMAIN_NAME}" \
        -addext "subjectAltName=DNS:${DOMAIN_NAME}"
fi

chmod 600 /etc/nginx/ssl/inception.key
chmod 644 /etc/nginx/ssl/inception.crt

envsubst '${DOMAIN_NAME}' \
    < /etc/nginx/templates/default.conf.template \
    > /etc/nginx/sites-enabled/default

nginx -t

echo "Starting NGINX..."
exec "$@"
