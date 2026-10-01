FROM debian:bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        nginx \
        openssl \
        gettext-base \
    && rm -rf /var/lib/apt/lists/*

RUN rm -f /etc/nginx/sites-enabled/default \
    && mkdir -p /etc/nginx/ssl /var/www/html

COPY conf/default.conf.template /etc/nginx/templates/default.conf.template
COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 755 /usr/local/bin/entrypoint.sh

EXPOSE 443

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
