#!/bin/bash
# ============================================================================
# Fix n8n Deployment Issues
# Addresses: DB password mismatch, worker placement, OrbStack constraints
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo "Fixing n8n Deployment Issues"
echo -e "==========================================${NC}\n"

# ============================================================================
# Issue 1: Check environment variables
# ============================================================================
echo -e "${YELLOW}[1] Checking environment variables...${NC}"

if [ ! -f .env ]; then
    echo -e "${RED}✗ .env file not found${NC}"
    exit 1
fi

source .env

if [ -z "$POSTGRES_PASSWORD" ] || [ "$POSTGRES_PASSWORD" == "CHANGE_ME" ]; then
    echo -e "${RED}✗ POSTGRES_PASSWORD not set in .env${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Environment variables loaded${NC}"
echo -e "  DB User: ${POSTGRES_USER}"
echo -e "  DB Name: ${POSTGRES_DB}"

# ============================================================================
# Issue 2: Check PostgreSQL password
# ============================================================================
echo -e "\n${YELLOW}[2] Testing PostgreSQL connection...${NC}"

# Get postgres container
POSTGRES_CONTAINER=$(docker ps -q -f name=n8n_postgres)

if [ -z "$POSTGRES_CONTAINER" ]; then
    echo -e "${RED}✗ PostgreSQL container not found${NC}"
    exit 1
fi

# Test connection
if docker exec $POSTGRES_CONTAINER psql -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT 1" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ PostgreSQL connection successful${NC}"
else
    echo -e "${RED}✗ PostgreSQL connection failed${NC}"
    echo -e "${YELLOW}This usually means the password in .env doesn't match the database${NC}"
    echo -e "${YELLOW}Solution: Recreate the postgres volume with correct password${NC}"
    
    read -p "Recreate PostgreSQL with current .env password? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Stopping and removing PostgreSQL service...${NC}"
        docker service rm n8n_postgres
        docker volume rm n8n_postgres_data || true
        
        echo -e "${BLUE}Redeploying stack...${NC}"
        docker stack deploy -c docker-stack.production.yml n8n
        
        echo -e "${GREEN}✓ PostgreSQL recreated. Wait 30 seconds for initialization...${NC}"
        sleep 30
    else
        exit 1
    fi
fi

# ============================================================================
# Issue 3: Check OrbStack node configuration
# ============================================================================
echo -e "\n${YELLOW}[3] Checking Docker Swarm nodes...${NC}"

NODE_COUNT=$(docker node ls --format "{{.Hostname}}" | wc -l)
MANAGER_COUNT=$(docker node ls --filter "role=manager" --format "{{.Hostname}}" | wc -l)
WORKER_COUNT=$(docker node ls --filter "role=worker" --format "{{.Hostname}}" | wc -l)

echo -e "  Total nodes: ${NODE_COUNT}"
echo -e "  Manager nodes: ${MANAGER_COUNT}"
echo -e "  Worker nodes: ${WORKER_COUNT}"

if [ "$WORKER_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠ No worker nodes found${NC}"
    echo -e "${YELLOW}Since you're on OrbStack (single node), workers won't run in global mode${NC}"
    echo -e "${YELLOW}Solution: Change worker deployment to run on manager node${NC}"
fi

# ============================================================================
# Issue 4: Get current node labels
# ============================================================================
echo -e "\n${YELLOW}[4] Checking node labels...${NC}"

CURRENT_NODE=$(docker node ls --format "{{.Hostname}}" | head -1)
echo -e "  Current node: ${CURRENT_NODE}"

NODE_LABELS=$(docker node inspect $CURRENT_NODE --format '{{range $k, $v := .Spec.Labels}}{{$k}}={{$v}} {{end}}')
if [ -z "$NODE_LABELS" ]; then
    echo -e "  No custom labels"
else
    echo -e "  Labels: ${NODE_LABELS}"
fi

# ============================================================================
# Issue 5: Fix the deployment for single-node setup
# ============================================================================
echo -e "\n${YELLOW}[5] Creating OrbStack-compatible stack file...${NC}"

cat > docker-stack.orbstack.yml << 'EOFSTACK'
# ============================================================================
# n8n Production Stack - OrbStack Single-Node Configuration
# All services run on the single manager node (no separate workers)
# ============================================================================
version: '3.8'

volumes:
  postgres_data:
    driver: local
  redis_data:
    driver: local
  n8n_webhook_data:
    driver: local
  n8n_mcp_data:
    driver: local
  n8n_worker_data:
    driver: local
  traefik_data:
    driver: local
  letsencrypt:
    driver: local
  prometheus_data:
    driver: local
  grafana_data:
    driver: local
  alertmanager_data:
    driver: local

networks:
  n8n-network:
    driver: overlay
    attachable: true

services:
  postgres:
    image: postgres:16-alpine
    deploy:
      replicas: 1
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
      TZ: ${TIMEZONE}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -h localhost -U ${POSTGRES_USER} -d ${POSTGRES_DB}']
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
    networks:
      - n8n-network
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "5"

  redis:
    image: redis:7-alpine
    deploy:
      replicas: 1
    command: >
      redis-server
      --appendonly yes
      --appendfsync everysec
      --maxmemory ${REDIS_MAXMEMORY:-512mb}
      --maxmemory-policy ${REDIS_MAXMEMORY_POLICY:-allkeys-lru}
      --requirepass ${REDIS_PASSWORD}
      --port ${REDIS_PORT:-6379}
    volumes:
      - redis_data:/data
    healthcheck:
      test: ['CMD', 'redis-cli', '-p', '${REDIS_PORT:-6379}', '-a', '${REDIS_PASSWORD}', 'ping']
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 10s
    networks:
      - n8n-network
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "5"

  traefik:
    image: traefik:v3.5.3
    deploy:
      replicas: 1
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - letsencrypt:/letsencrypt
      - ./config/traefik/traefik.yml:/etc/traefik/traefik.yml:ro
      - ./config/traefik/dynamic.yml:/etc/traefik/dynamic.yml:ro
    healthcheck:
      test: ['CMD', 'wget', '--no-verbose', '--tries=1', '--spider', 'http://localhost:8080/ping']
      interval: 10s
      timeout: 3s
      retries: 3
      start_period: 5s
    networks:
      - n8n-network
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "5"

  n8n-webhook:
    image: docker.n8n.io/n8nio/n8n:latest
    deploy:
      replicas: 1
      labels:
        - "traefik.enable=true"
        - "traefik.docker.network=n8n_n8n-network"
        - "traefik.http.routers.n8n.rule=Host(`${N8N_HOST}`)"
        - "traefik.http.routers.n8n.entrypoints=websecure"
        - "traefik.http.routers.n8n.tls.certresolver=letsencrypt"
        - "traefik.http.routers.n8n.priority=10"
        - "traefik.http.services.n8n.loadbalancer.server.port=5678"
        - "traefik.http.routers.n8n.middlewares=security-headers@file,compress@file"
    environment:
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: ${POSTGRES_DB}
      DB_POSTGRESDB_USER: ${POSTGRES_USER}
      DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_POSTGRESDB_POOL_SIZE: 4
      
      EXECUTIONS_MODE: queue
      QUEUE_BULL_REDIS_HOST: redis
      QUEUE_BULL_REDIS_PORT: ${REDIS_PORT:-6379}
      QUEUE_BULL_REDIS_DB: 0
      QUEUE_BULL_REDIS_PASSWORD: ${REDIS_PASSWORD}
      QUEUE_HEALTH_CHECK_ACTIVE: "true"
      
      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
      N8N_BASIC_AUTH_ACTIVE: "true"
      N8N_BASIC_AUTH_USER: ${N8N_BASIC_AUTH_USER}
      N8N_BASIC_AUTH_PASSWORD: ${N8N_BASIC_AUTH_PASSWORD}
      N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS: "false"
      
      N8N_HOST: ${N8N_HOST}
      N8N_PORT: 5678
      N8N_PROTOCOL: https
      WEBHOOK_URL: "https://${N8N_HOST}/"
      N8N_EDITOR_BASE_URL: "https://${N8N_HOST}/"
      
      EXECUTIONS_DATA_SAVE_ON_SUCCESS: all
      EXECUTIONS_DATA_SAVE_ON_ERROR: all
      EXECUTIONS_DATA_SAVE_ON_PROGRESS: "true"
      EXECUTIONS_DATA_PRUNE: "true"
      EXECUTIONS_DATA_MAX_AGE: 336
      
      GENERIC_TIMEZONE: ${TIMEZONE}
      TZ: ${TIMEZONE}
      
      N8N_PAYLOAD_SIZE_MAX: 16
      N8N_METRICS: "true"
      
      LOG_LEVEL: info
      LOG_OUTPUT: console
    volumes:
      - n8n_webhook_data:/home/node/.n8n
    healthcheck:
      test: ["CMD-SHELL", "wget --spider -q http://localhost:5678/healthz || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    networks:
      - n8n-network
    logging:
      driver: json-file
      options:
        max-size: "100m"
        max-file: "10"

  n8n-mcp:
    image: docker.n8n.io/n8nio/n8n:latest
    deploy:
      replicas: 1
      labels:
        - "traefik.enable=true"
        - "traefik.docker.network=n8n_n8n-network"
        - "traefik.http.routers.n8n-mcp.rule=Host(`${N8N_HOST}`) && PathPrefix(`/mcp`)"
        - "traefik.http.routers.n8n-mcp.entrypoints=websecure"
        - "traefik.http.routers.n8n-mcp.tls.certresolver=letsencrypt"
        - "traefik.http.routers.n8n-mcp.priority=100"
        - "traefik.http.services.n8n-mcp.loadbalancer.server.port=5678"
        - "traefik.http.routers.n8n-mcp.middlewares=mcp-sse@file"
    environment:
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: ${POSTGRES_DB}
      DB_POSTGRESDB_USER: ${POSTGRES_USER}
      DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_POSTGRESDB_POOL_SIZE: 2
      
      EXECUTIONS_MODE: queue
      QUEUE_BULL_REDIS_HOST: redis
      QUEUE_BULL_REDIS_PORT: ${REDIS_PORT:-6379}
      QUEUE_BULL_REDIS_DB: 0
      QUEUE_BULL_REDIS_PASSWORD: ${REDIS_PASSWORD}
      
      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
      N8N_BASIC_AUTH_ACTIVE: "true"
      N8N_BASIC_AUTH_USER: ${N8N_BASIC_AUTH_USER}
      N8N_BASIC_AUTH_PASSWORD: ${N8N_BASIC_AUTH_PASSWORD}
      N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS: "false"
      
      N8N_HOST: ${N8N_HOST}
      N8N_PORT: 5678
      N8N_PROTOCOL: https
      WEBHOOK_URL: "https://${N8N_HOST}/"
      N8N_EDITOR_BASE_URL: "https://${N8N_HOST}/"
      
      GENERIC_TIMEZONE: ${TIMEZONE}
      TZ: ${TIMEZONE}
      
      LOG_LEVEL: info
      LOG_OUTPUT: console
    volumes:
      - n8n_mcp_data:/home/node/.n8n
    healthcheck:
      test: ["CMD-SHELL", "wget --spider -q http://localhost:5678/healthz || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    networks:
      - n8n-network
    logging:
      driver: json-file
      options:
        max-size: "100m"
        max-file: "10"

  n8n-worker:
    image: docker.n8n.io/n8nio/n8n:latest
    deploy:
      replicas: 2
    command: n8n worker --concurrency=${N8N_WORKER_CONCURRENCY:-10}
    environment:
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: ${POSTGRES_DB}
      DB_POSTGRESDB_USER: ${POSTGRES_USER}
      DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_POSTGRESDB_POOL_SIZE: 4
      
      EXECUTIONS_MODE: queue
      QUEUE_BULL_REDIS_HOST: redis
      QUEUE_BULL_REDIS_PORT: ${REDIS_PORT:-6379}
      QUEUE_BULL_REDIS_DB: 0
      QUEUE_BULL_REDIS_PASSWORD: ${REDIS_PASSWORD}
      
      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
      N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS: "false"
      
      GENERIC_TIMEZONE: ${TIMEZONE}
      TZ: ${TIMEZONE}
      
      N8N_PAYLOAD_SIZE_MAX: 16
      
      LOG_LEVEL: info
      LOG_OUTPUT: console
    volumes:
      - n8n_worker_data:/home/node/.n8n
    healthcheck:
      test: ["CMD-SHELL", "ps aux | grep -v grep | grep -q 'n8n worker' || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 60s
    networks:
      - n8n-network
    logging:
      driver: json-file
      options:
        max-size: "100m"
        max-file: "10"

  prometheus:
    image: prom/prometheus:latest
    deploy:
      replicas: 1
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus"
      - "--storage.tsdb.retention.time=45d"
      - "--web.listen-address=:9090"
    ports:
      - "9090:9090"
    volumes:
      - prometheus_data:/prometheus
      - ./config/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    networks:
      - n8n-network
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "5"

  grafana:
    image: grafana/grafana:latest
    deploy:
      replicas: 1
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.grafana.rule=Host(`grafana.${N8N_HOST}`)"
        - "traefik.http.routers.grafana.entrypoints=websecure"
        - "traefik.http.routers.grafana.tls.certresolver=letsencrypt"
        - "traefik.http.services.grafana.loadbalancer.server.port=3000"
    environment:
      GF_SECURITY_ADMIN_USER: ${GRAFANA_ADMIN_USER}
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD}
      GF_SERVER_ROOT_URL: "https://grafana.${N8N_HOST}"
      TZ: ${TIMEZONE}
    volumes:
      - grafana_data:/var/lib/grafana
    networks:
      - n8n-network
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "5"

  alertmanager:
    image: prom/alertmanager:latest
    deploy:
      replicas: 1
    command:
      - "--config.file=/etc/alertmanager/alertmanager.yml"
      - "--storage.path=/alertmanager"
    ports:
      - "9093:9093"
    volumes:
      - alertmanager_data:/alertmanager
      - ./config/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
    networks:
      - n8n-network
    logging:
      driver: json-file
      options:
        max-size: "30m"
        max-file: "3"
EOFSTACK

echo -e "${GREEN}✓ Created docker-stack.orbstack.yml${NC}"

# ============================================================================
# Issue 6: Redeploy with fixed configuration
# ============================================================================
echo -e "\n${YELLOW}[6] Redeploying stack with OrbStack configuration...${NC}"

read -p "Redeploy now? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker stack deploy -c docker-stack.orbstack.yml n8n
    echo -e "${GREEN}✓ Stack redeployed${NC}"
    echo -e "${BLUE}Waiting 30 seconds for services to start...${NC}"
    sleep 30
else
    echo -e "${YELLOW}Skipping redeploy. Run manually: docker stack deploy -c docker-stack.orbstack.yml n8n${NC}"
fi

# ============================================================================
# Final Status
# ============================================================================
echo -e "\n${YELLOW}[7] Final service status...${NC}"
docker service ls

echo -e "\n${BLUE}=========================================="
echo "Deployment Fix Complete"
echo -e "==========================================${NC}"

echo -e "\n${YELLOW}Next steps:${NC}"
echo -e "1. Check service logs: ${BLUE}docker service logs n8n_n8n-mcp${NC}"
echo -e "2. Verify all services running: ${BLUE}docker stack ps n8n${NC}"
echo -e "3. Test n8n: ${BLUE}https://${N8N_HOST}${NC}"
