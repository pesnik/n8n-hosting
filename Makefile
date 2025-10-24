# ============================================================================
# n8n Docker Stack Management
# ============================================================================

# Include environment variables
include .env
export

# Docker Stack name
STACK_NAME := n8n
NETWORK_NAME := n8n-network

# Phony targets
.PHONY: help deploy down logs clean ps env-check config-check postgres-cli redis-cli restart monitor network-create network-remove

# ============================================================================
# MAIN TARGETS
# ============================================================================

help: ## Show this help
	@echo "n8n Docker Stack Management"
	@echo ""
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

network-create: ## Create external network
	@echo "Creating external network $(NETWORK_NAME)..."
	@-docker network create --driver overlay --attachable $(NETWORK_NAME) 2>/dev/null && echo "✓ Network created" || echo "ℹ Network already exists or error"

network-remove: ## Remove external network
	@echo "Removing external network $(NETWORK_NAME)..."
	@-docker network rm $(NETWORK_NAME) 2>/dev/null && echo "✓ Network removed" || echo "ℹ Network not found or error"

deploy: env-check config-check network-create ## Deploy the stack (requires .env file)
	@echo "Deploying $(STACK_NAME) stack..."
	docker stack deploy -c docker-stack.yml $(STACK_NAME)
	@echo "Stack deployed. Run 'make ps' to check status."

down: ## Remove the stack (but keep network)
	@echo "Removing $(STACK_NAME) stack..."
	docker stack rm $(STACK_NAME)
	@echo "Stack removed."

restart: down deploy ## Restart the stack

# ============================================================================
# MONITORING & LOGS
# ============================================================================

ps: ## Show stack services status
	@echo "Stack services status:"
	@docker stack ps $(STACK_NAME) || true
	@echo ""
	@echo "Stack services:"
	@docker stack services $(STACK_NAME) || true
	@echo ""
	@echo "Network info:"
	@docker network ls | grep $(NETWORK_NAME) || true

logs: ## Follow logs from all services
	@docker service logs -f $(STACK_NAME)_n8n-webhook

logs-mcp: ## Follow logs from MCP service
	@docker service logs -f $(STACK_NAME)_n8n-mcp

logs-postgres: ## Follow logs from PostgreSQL
	@docker service logs -f $(STACK_NAME)_postgres

logs-redis: ## Follow logs from Redis
	@docker service logs -f $(STACK_NAME)_redis

logs-worker: ## Follow logs from workers
	@docker service logs -f $(STACK_NAME)_n8n-worker

monitor: ## Monitor all services logs in real-time
	@watch -n 2 'docker service ls | grep $(STACK_NAME)'

# ============================================================================
# DATABASE & REDIS MANAGEMENT
# ============================================================================

postgres-cli: ## Connect to PostgreSQL database
	@echo "Connecting to PostgreSQL..."
	@docker exec -it $$(docker ps -q -f name=$(STACK_NAME)_postgres) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

redis-cli: ## Connect to Redis
	@echo "Connecting to Redis..."
	@docker exec -it $$(docker ps -q -f name=$(STACK_NAME)_redis) redis-cli -a $(REDIS_PASSWORD) -p $(REDIS_PORT)

# ============================================================================
# CLEANUP
# ============================================================================

clean: down ## Remove stack and clean volumes (DESTRUCTIVE)
	@echo "Removing all volumes..."
	@docker volume prune -f
	@echo "Cleanup complete."

clean-nuke: down network-remove ## Nuclear option - remove everything (VERY DESTRUCTIVE)
	@echo "Removing all containers, volumes, and networks..."
	@docker system prune -a -f --volumes
	@echo "Nuclear cleanup complete."

clean-full: down network-remove ## Full cleanup - stack, network, volumes
	@echo "Removing stack, network, and volumes..."
	@docker volume prune -f
	@echo "Full cleanup complete."

# ============================================================================
# VALIDATION & CHECKS
# ============================================================================

env-check: ## Check if required environment variables are set
	@echo "Checking environment variables..."
	@test -n "$(POSTGRES_PASSWORD)" || (echo "ERROR: POSTGRES_PASSWORD is not set"; exit 1)
	@test -n "$(N8N_ENCRYPTION_KEY)" || (echo "ERROR: N8N_ENCRYPTION_KEY is not set"; exit 1)
	@test -n "$(N8N_HOST)" || (echo "ERROR: N8N_HOST is not set"; exit 1)
	@test -n "$(N8N_BASIC_AUTH_PASSWORD)" || (echo "ERROR: N8N_BASIC_AUTH_PASSWORD is not set"; exit 1)
	@echo "✓ All required environment variables are set"

config-check: ## Validate docker-stack.yml configuration
	@echo "Validating docker-stack.yml..."
	@test -f docker-stack.yml || (echo "ERROR: docker-stack.yml not found"; exit 1)
	@grep -q "external: true" docker-stack.yml || (echo "WARNING: Network not configured as external in docker-stack.yml"; exit 1)
	@echo "✓ docker-stack.yml found and valid"

validate: env-check config-check ## Run all validation checks
	@echo "✓ All validation checks passed"

# ============================================================================
# DEVELOPMENT & DEBUGGING
# ============================================================================

debug-env: ## Show current environment variables (without passwords)
	@echo "Current environment:"
	@echo "  POSTGRES_USER: $(POSTGRES_USER)"
	@echo "  POSTGRES_DB: $(POSTGRES_DB)"
	@echo "  REDIS_PORT: $(REDIS_PORT)"
	@echo "  N8N_HOST: $(N8N_HOST)"
	@echo "  N8N_BASIC_AUTH_USER: $(N8N_BASIC_AUTH_USER)"
	@echo "  TIMEZONE: $(TIMEZONE)"

inspect-mcp: ## Inspect MCP service configuration
	@docker service inspect $(STACK_NAME)_n8n-mcp --format='{{json .Spec.TaskTemplate.ContainerSpec.Env}}' | jq '.'

inspect-webhook: ## Inspect webhook service configuration
	@docker service inspect $(STACK_NAME)_n8n-webhook --format='{{json .Spec.TaskTemplate.ContainerSpec.Env}}' | jq '.'

network-info: ## Show network information
	@docker network inspect $(NETWORK_NAME) 2>/dev/null | jq '.' || echo "Network $(NETWORK_NAME) not found"

# ============================================================================
# BACKUP & RESTORE (Optional)
# ============================================================================

backup-db: ## Backup PostgreSQL database
	@mkdir -p backups
	@docker exec $$(docker ps -q -f name=$(STACK_NAME)_postgres) pg_dump -U $(POSTGRES_USER) $(POSTGRES_DB) > backups/backup_$$(date +%Y%m%d_%H%M%S).sql
	@echo "Database backup created"

list-backups: ## List available backups
	@ls -la backups/ 2>/dev/null || echo "No backups found"

# Default target
.DEFAULT_GOAL := help
