COMPOSE = sudo docker compose --env-file srcs/.env -f srcs/docker-compose.yml

.DEFAULT_GOAL := all

.PHONY: all up down logs ps db-shell check-config \
	test-https test-http test-tls inspect-volumes reset

all: up

up:
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs --tail=100 -f

ps:
	$(COMPOSE) ps -a

reset:
	@echo "WARNING: deleting containers, network and persistent volumes"
	$(COMPOSE) down -v --remove-orphans
	$(COMPOSE) up -d --build

db-shell:
	$(COMPOSE) exec mariadb sh -c 'exec mariadb --protocol=TCP -h 127.0.0.1 -u "$$DB_USER" -p "$$DB_NAME"'

check-config:
	$(COMPOSE) config -q

test-https:
	@set -eu; \
	domain="$$( $(COMPOSE) exec -T nginx printenv DOMAIN_NAME )"; \
	echo "Testing https://$$domain on VM port 443"; \
	code="$$(curl -ksS -I --connect-timeout 5 --max-time 15 \
		--resolve "$$domain:443:127.0.0.1" \
		-o /dev/null -w '%{http_code}' "https://$$domain")"; \
	echo "HTTP status: $$code"; \
	test "$$code" = "200"

test-http:
	@set -eu; \
	domain="$$( $(COMPOSE) exec -T nginx printenv DOMAIN_NAME )"; \
	echo "Checking that VM port 80 refuses connections"; \
	status=0; \
	curl -sS -I --connect-timeout 5 --max-time 15 \
		--resolve "$$domain:80:127.0.0.1" \
		"http://$$domain" >/dev/null 2>&1 || status=$$?; \
	if [ "$$status" -eq 7 ]; then \
		echo "PASS: connection to port 80 refused"; \
	else \
		echo "FAIL: expected curl exit code 7, got $$status"; \
		exit 1; \
	fi

test-tls:
	@set -eu; \
	domain="$$( $(COMPOSE) exec -T nginx printenv DOMAIN_NAME )"; \
	for version in 1.2 1.3; do \
		echo "Testing TLS $$version"; \
		code="$$(curl -ksS -I --connect-timeout 5 --max-time 15 \
			--tlsv$$version --tls-max "$$version" \
			--resolve "$$domain:443:127.0.0.1" \
			-o /dev/null -w '%{http_code}' "https://$$domain")"; \
		echo "HTTP status: $$code"; \
		test "$$code" = "200"; \
	done; \
	for protocol in tls1 tls1_1; do \
		echo "Checking rejection of $$protocol"; \
		output="$$(timeout 10 openssl s_client \
			-connect 127.0.0.1:443 -servername "$$domain" \
			-$$protocol -cipher 'DEFAULT:@SECLEVEL=0' \
			-brief </dev/null 2>&1 || true)"; \
		if printf '%s\n' "$$output" | grep -Fq 'alert protocol version'; then \
			echo "PASS: protocol rejected by server"; \
		else \
			printf '%s\n' "$$output"; \
			echo "FAIL: expected a protocol-version alert"; \
			exit 1; \
		fi; \
	done

inspect-volumes:
	@set -eu; \
	for service in mariadb wordpress nginx; do \
		container="$$( $(COMPOSE) ps -q "$$service" )"; \
		if [ -z "$$container" ]; then \
			echo "Service $$service is not running"; \
			exit 1; \
		fi; \
		echo "Service: $$service"; \
		sudo docker inspect "$$container" \
			--format '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name "|" .Source "->" .Destination "| RW=" .RW}}{{end}}{{end}}'; \
	done
