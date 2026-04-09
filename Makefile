# ─── Config ───────────────────────────────────────────────────────────────────
include .env
export

COMPOSE        := docker compose
CONTAINER      := litmarket_db
NETWORK        := litmarket_network
DB_INNER_HOST  := db
DB_INNER_PORT  := 3306

# Default source SQL dump path
SQL_SOURCE ?= /home/grey/LitmarketProject/litmarket/mysql-init.sql
# Local copy used during import (mounted into container)
SQL_FILE    := $(CURDIR)/mysql-init.sql

# mysql:8.0-debian — Debian-based, has apt-get + pv available.
# mysql:8.0 (default) is Oracle Linux 9 — no pv in repos.
# mariadb-client (Alpine) can't auth against MySQL 8.0 caching_sha2_password.
IMPORT_IMAGE := mysql:8.0-debian

# Allow passing path as positional arg: make import /path/to/dump.sql
_IMPORT_ARG := $(filter-out import fresh, $(MAKECMDGOALS))
ifneq ($(_IMPORT_ARG),)
SQL_SOURCE  := $(_IMPORT_ARG)
.PHONY: $(_IMPORT_ARG)
endif

.PHONY: up down restart destroy logs ps shell import fresh help %
# Catch-all: treat unknown targets (i.e. the path arg) as no-ops
%:
	@:

# ─── Container management ─────────────────────────────────────────────────────

up: ## Start containers in background
	$(COMPOSE) up -d
	@echo ""
	@echo "MySQL is starting on port $(DB_PORT)..."
	@echo "Run 'make logs' to watch startup progress."

down: ## Stop containers (data is preserved)
	$(COMPOSE) down

restart: ## Restart containers
	$(COMPOSE) restart

destroy: ## Stop containers AND delete all data (irreversible!)
	@echo "WARNING: This will permanently delete all database data."
	@read -p "Are you sure? [y/N] " ans && [ "$$ans" = "y" ]
	$(COMPOSE) down -v

logs: ## Follow container logs
	$(COMPOSE) logs -f db

ps: ## Show container status
	$(COMPOSE) ps

shell: ## Open MySQL shell inside container
	docker exec -it $(CONTAINER) mysql -u$(DB_USERNAME) -p$(DB_PASSWORD) $(DB_DATABASE)

# ─── Database import ──────────────────────────────────────────────────────────

import: up ## Import SQL dump with progress (drops & recreates DB first)
	@if [ ! -f "$(SQL_SOURCE)" ]; then \
		echo "ERROR: SQL file not found: $(SQL_SOURCE)"; \
		echo "Override: make import SQL_SOURCE=/path/to/dump.sql"; \
		exit 1; \
	fi
	@echo ">>> Copying dump from $(SQL_SOURCE)..."
	@cp "$(SQL_SOURCE)" "$(SQL_FILE)"
	@echo ">>> Waiting for MySQL to be ready..."
	@docker run --rm \
		--network $(NETWORK) \
		--env MYSQL_PWD=$(DB_ROOT_PASSWORD) \
		$(IMPORT_IMAGE) sh -c \
		'until mysqladmin ping -h$(DB_INNER_HOST) -uroot --silent 2>/dev/null; do \
		   printf "."; sleep 2; \
		 done; echo " ready!"'
	@echo ">>> Resetting MySQL state (dropping all user databases and users)..."
	@docker run --rm \
		--network $(NETWORK) \
		--env MYSQL_PWD=$(DB_ROOT_PASSWORD) \
		$(IMPORT_IMAGE) sh -c '\
		mysql -h$(DB_INNER_HOST) -uroot -N -e \
		  "SELECT CONCAT(\"DROP DATABASE IF EXISTS \`\", schema_name, \"\`;\") \
		   FROM information_schema.schemata \
		   WHERE schema_name NOT IN (\"information_schema\",\"mysql\",\"performance_schema\",\"sys\")" \
		| mysql -h$(DB_INNER_HOST) -uroot; \
		mysql -h$(DB_INNER_HOST) -uroot -N -e \
		  "SELECT CONCAT(\"DROP USER IF EXISTS \`\", user, \"\`@\`\", host, \"\`;\") \
		   FROM mysql.user \
		   WHERE user NOT IN (\"root\",\"mysql.sys\",\"mysql.infoschema\",\"mysql.session\",\"\")" \
		| mysql -h$(DB_INNER_HOST) -uroot; \
		echo "Reset done." && \
		mysql -h$(DB_INNER_HOST) -uroot \
		  -e "CREATE DATABASE \`$(DB_DATABASE)\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"'
	@echo ">>> Importing with progress..."
	@docker run --rm \
		--network $(NETWORK) \
		--env MYSQL_PWD=$(DB_ROOT_PASSWORD) \
		--env DEBIAN_FRONTEND=noninteractive \
		-v "$(SQL_FILE):/dump.sql:ro" \
		$(IMPORT_IMAGE) sh -c \
		'apt-get update -qq > /dev/null 2>&1 && apt-get install -y -qq pv > /dev/null 2>&1 && \
		 mysql -h$(DB_INNER_HOST) -uroot -e "RESET MASTER;" && \
		 pv -petra /dump.sql | mysql -h$(DB_INNER_HOST) -uroot $(DB_DATABASE)'
	@echo ">>> Restoring app user '$(DB_USERNAME)' and database '$(DB_DATABASE)'..."
	@docker run --rm \
		--network $(NETWORK) \
		--env MYSQL_PWD=$(DB_ROOT_PASSWORD) \
		$(IMPORT_IMAGE) \
		mysql -h$(DB_INNER_HOST) -uroot \
		  -e "CREATE DATABASE IF NOT EXISTS \`$(DB_DATABASE)\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; \
		      CREATE USER IF NOT EXISTS '$(DB_USERNAME)'@'%' IDENTIFIED BY '$(DB_PASSWORD)'; \
		      GRANT ALL PRIVILEGES ON *.* TO '$(DB_USERNAME)'@'%' WITH GRANT OPTION; \
		      FLUSH PRIVILEGES;"
	@echo ""
	@echo ">>> Import complete!"

fresh: import ## Alias for import (drop + reimport)

# ─── Help ─────────────────────────────────────────────────────────────────────

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
