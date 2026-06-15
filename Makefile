# ═══════════════════════════════════════════════════════════════════════════════
# AL-MIZAN — Docker Compose Convenience Commands
# All commands must be run from the al-mizan-deployments/ directory.
# ═══════════════════════════════════════════════════════════════════════════════

INFRA  = docker compose -f docker-compose.infra.yml
APP    = docker compose -f docker-compose.infra.yml -f docker-compose.yml
DEV    = docker compose -f docker-compose.infra.yml -f docker-compose.yml -f docker-compose.dev.yml
AI     = docker compose -f docker-compose.infra.yml -f docker-compose.yml -f docker-compose.ai.yml
ALL    = docker compose -f docker-compose.infra.yml -f docker-compose.yml -f docker-compose.dev.yml -f docker-compose.ai.yml

.PHONY: help up up-dev up-ai up-all down down-all infra logs ps build build-dev restart db-create

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  Port map:"
	@echo "    client       → http://localhost:4000"
	@echo "    api-gateway  → http://localhost:3000"
	@echo "    auth         → http://localhost:3001"
	@echo "    users        → http://localhost:3002"
	@echo "    audit        → http://localhost:3009"
	@echo "    ao           → http://localhost:8003"
	@echo "    soumission   → http://localhost:8004"
	@echo "    documents    → http://localhost:8005"
	@echo "    evaluation   → http://localhost:8008"
	@echo "    commission   → http://localhost:8007"
	@echo "    recours      → http://localhost:8009"
	@echo "    notification → http://localhost:8010"
	@echo "    rabbitmq-ui  → http://localhost:15672  (guest/guest)"
	@echo "    minio-ui     → http://localhost:9001   (minioadmin/minioadmin)"

# ─── Infrastructure only ─────────────────────────────────────────────────────
infra: ## Start infrastructure (MySQL, Redis, RabbitMQ, MinIO)
	$(INFRA) up -d

infra-down: ## Stop infrastructure
	$(INFRA) down

# ─── Production ──────────────────────────────────────────────────────────────
up: ## Start all services in production mode (build + run)
	$(APP) up -d --build
	@echo ""
	@echo "✅  All services started. Client: http://localhost:4000"

down: ## Stop all services (keep volumes)
	$(APP) down

down-all: ## Stop everything and remove volumes (DESTRUCTIVE)
	$(APP) down -v --remove-orphans

# ─── Development (hot-reload) ─────────────────────────────────────────────────
up-dev: ## Start all services in dev mode (hot-reload via volume mounts)
	$(DEV) up --build
	@echo ""
	@echo "🔥  Dev stack running. Client: http://localhost:4000"

down-dev: ## Stop dev stack
	$(DEV) down

# ─── AI layer ────────────────────────────────────────────────────────────────
up-ai: ## Start app + AI orchestrator and agents
	$(AI) up -d --build

down-ai: ## Stop AI layer
	$(AI) down

# ─── Full stack (dev + AI) ────────────────────────────────────────────────────
up-all: ## Start everything: infra + app + AI (dev mode)
	$(ALL) up --build

down-all-dev: ## Stop full dev+AI stack
	$(ALL) down

# ─── Utilities ───────────────────────────────────────────────────────────────
logs: ## Follow logs for all running services
	$(APP) logs -f

ps: ## Show running service status
	$(APP) ps

build: ## Rebuild all production images (no cache)
	$(APP) build --no-cache

build-dev: ## Rebuild all dev images
	$(DEV) build --no-cache

restart: ## Restart all services (no rebuild)
	$(APP) restart

# ─── Database helpers ────────────────────────────────────────────────────────
db-create: ## Create all MySQL databases (run after infra is up)
	docker exec al-mizan-mysql mysql -u root -ppassword -e "\
		CREATE DATABASE IF NOT EXISTS auth_db; \
		CREATE DATABASE IF NOT EXISTS al_mizan_users; \
		CREATE DATABASE IF NOT EXISTS ao_db; \
		CREATE DATABASE IF NOT EXISTS soumission_db; \
		CREATE DATABASE IF NOT EXISTS document_db; \
		CREATE DATABASE IF NOT EXISTS evaluation_db; \
		CREATE DATABASE IF NOT EXISTS commission_db; \
		CREATE DATABASE IF NOT EXISTS recours_db; \
		CREATE DATABASE IF NOT EXISTS notif_db; \
		CREATE DATABASE IF NOT EXISTS audit_db;" 2>/dev/null \
		&& echo "✅  All databases created."

db-reset: ## Drop and recreate all databases (DESTRUCTIVE)
	docker exec al-mizan-mysql mysql -u root -ppassword -e "\
		DROP DATABASE IF EXISTS auth_db; DROP DATABASE IF EXISTS al_mizan_users; \
		DROP DATABASE IF EXISTS ao_db; DROP DATABASE IF EXISTS soumission_db; \
		DROP DATABASE IF EXISTS document_db; DROP DATABASE IF EXISTS evaluation_db; \
		DROP DATABASE IF EXISTS commission_db; DROP DATABASE IF EXISTS recours_db; \
		DROP DATABASE IF EXISTS notif_db; DROP DATABASE IF EXISTS audit_db;" 2>/dev/null
	$(MAKE) db-create
