COMPOSE = sudo docker compose --env-file srcs/.env -f srcs/docker-compose.yml

.DEFAULT_GOAL := all

.PHONY: all up down logs ps db-shell

all: up

up:
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs --tail=100 -f

ps:
	$(COMPOSE) ps -a

db-shell:
	$(COMPOSE) exec mariadb sh -c 'exec mariadb --protocol=TCP -h 127.0.0.1 -u "$$DB_USER" -p "$$DB_NAME"'
