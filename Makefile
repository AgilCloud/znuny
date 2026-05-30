SHELL := /bin/sh

COMPOSE ?= docker compose
ENV_FILE ?= .env
SECRETS_DIR ?= .secrets
BACKUP_DIR ?= backups
ZNUNY_HTTP_PORT ?= 8080

DB_SECRET := $(SECRETS_DIR)/znuny_db_password
ADMIN_SECRET := $(SECRETS_DIR)/znuny_admin_password

.DEFAULT_GOAL := help

.PHONY: help check-env env build config up down logs ps smoke health lint backup restore clean

help: ## Lista comandos principais / list main commands.
	@awk 'BEGIN {FS = ":.*##"; printf "Uso / Usage: make <target>\n\n"} /^[a-zA-Z_-]+:.*##/ {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

env: ## Cria .env e secrets locais sem sobrescrever / create local .env and secrets.
	@test ! -f $(ENV_FILE) || { echo "$(ENV_FILE) ja existe; nada alterado."; exit 0; }
	@mkdir -p $(SECRETS_DIR)
	@db_pass="$$(openssl rand -base64 32 2>/dev/null || date | shasum | awk '{print $$1}')"; \
	admin_pass="$$(openssl rand -base64 32 2>/dev/null || date | shasum | awk '{print $$1}')"; \
	umask 077; \
	printf "%s\n" "$$db_pass" > $(DB_SECRET); \
	printf "%s\n" "$$admin_pass" > $(ADMIN_SECRET); \
		sed \
			-e "s|^ZNUNY_HTTP_PORT=.*|ZNUNY_HTTP_PORT=$(ZNUNY_HTTP_PORT)|" \
			.env.example > $(ENV_FILE); \
	echo "Criado $(ENV_FILE), $(DB_SECRET) e $(ADMIN_SECRET)."

check-env:
	@test -f $(ENV_FILE) || { echo "$(ENV_FILE) ausente. Execute: make env"; exit 2; }
	@test -f $(DB_SECRET) || { echo "$(DB_SECRET) ausente. Execute: make env"; exit 2; }
	@test -f $(ADMIN_SECRET) || { echo "$(ADMIN_SECRET) ausente. Execute: make env"; exit 2; }

build: check-env ## Constrói a imagem local / build local image.
	$(COMPOSE) build

config: check-env ## Valida e renderiza compose / validate and render compose.
	$(COMPOSE) config

up: check-env ## Sobe stack em background / start stack in background.
	$(COMPOSE) up -d

down: ## Para containers sem remover volumes / stop containers, keep volumes.
	$(COMPOSE) down

logs: ## Segue logs; use SERVICE=znuny ou db / follow logs.
	$(COMPOSE) logs -f --tail=200 $(SERVICE)

ps: ## Mostra status dos servicos / show service status.
	$(COMPOSE) ps

smoke: ## Teste HTTP simples / simple HTTP smoke test.
	@port="$$(grep -E '^ZNUNY_HTTP_PORT=' $(ENV_FILE) 2>/dev/null | cut -d= -f2- || true)"; \
	port="$${port:-$(ZNUNY_HTTP_PORT)}"; \
	url="http://127.0.0.1:$$port/znuny/index.pl"; \
	echo "Smoke: $$url"; \
	curl -fsS "$$url" >/dev/null && echo "OK"

health: ## Mostra health dos containers / show container health.
	@$(COMPOSE) ps
	@$(COMPOSE) exec -T db pg_isready -U "$${ZNUNY_DB_USER:-znuny}" -d "$${ZNUNY_DB_NAME:-znuny}" -h 127.0.0.1

lint: check-env ## Valida compose e Makefile basico / basic lint checks.
	$(COMPOSE) config >/dev/null
	@$(MAKE) -n help >/dev/null
	@echo "OK"

backup: check-env ## Backup nao destrutivo em backups/ / non-destructive backup.
	@mkdir -p $(BACKUP_DIR)
	@stamp="$$(date +%Y%m%d-%H%M%S)"; \
	db_file="$(BACKUP_DIR)/znuny-db-$$stamp.sql"; \
	meta_file="$(BACKUP_DIR)/znuny-compose-$$stamp.yaml"; \
	$(COMPOSE) exec -T db pg_dump -U "$${ZNUNY_DB_USER:-znuny}" "$${ZNUNY_DB_NAME:-znuny}" > "$$db_file"; \
	$(COMPOSE) config > "$$meta_file"; \
	echo "Backup criado: $$db_file"; \
	echo "Compose snapshot: $$meta_file"

restore: check-env ## Restore protegido: BACKUP=arquivo.sql CONFIRM=restore / guarded restore.
	@test -n "$(BACKUP)" || { echo "Informe BACKUP=backups/arquivo.sql"; exit 2; }
	@test "$(CONFIRM)" = "restore" || { echo "Restore nao executado. Reexecute com CONFIRM=restore."; exit 2; }
	@test -f "$(BACKUP)" || { echo "Arquivo nao encontrado: $(BACKUP)"; exit 2; }
	$(COMPOSE) exec -T db psql -U "$${ZNUNY_DB_USER:-znuny}" "$${ZNUNY_DB_NAME:-znuny}" < "$(BACKUP)"

clean: ## Limpeza segura: para stack, preserva dados / safe clean, preserves data.
	$(COMPOSE) down --remove-orphans
	@echo "Volumes e secrets preservados. Para apagar dados, faca manualmente e com confirmacao humana."
