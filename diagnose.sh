#!/bin/bash
# ============================================================================
# Quick Diagnostic Script for n8n Deployment Issues
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "n8n Deployment Diagnostics"
echo "=========================================="

# Load environment
if [ -f .env ]; then
    source .env
else
    echo -e "${RED}✗ .env not found${NC}"
    exit 1
fi

echo -e "\n${YELLOW}1. Service Status${NC}"
docker service ls

echo -e "\n${YELLOW}2. Failed Services${NC}"
docker service ps n8n_n8n-mcp --no-trunc | grep -E "Failed|Shutdown" || echo "No failures"
docker service ps n8n_n8n-worker --no-trunc | grep -E "Failed|Shutdown" || echo "No failures"

echo -e "\n${YELLOW}3. Database Connection Test${NC}"
POSTGRES_CONTAINER=$(docker ps -q -f name=n8n_postgres)
if [ -n "$POSTGRES_CONTAINER" ]; then
    if docker exec $POSTGRES_CONTAINER psql -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT version();" 2>/dev/null; then
        echo -e "${GREEN}✓ PostgreSQL connection OK${NC}"
    else
        echo -e "${RED}✗ PostgreSQL connection FAILED${NC}"
        echo -e "  Check password in .env matches database"
    fi
else
    echo -e "${RED}✗ PostgreSQL container not found${NC}"
fi

echo -e "\n${YELLOW}4. Redis Connection Test${NC}"
REDIS_CONTAINER=$(docker ps -q -f name=n8n_redis)
if [ -n "$REDIS_CONTAINER" ]; then
    if docker exec $REDIS_CONTAINER redis-cli -p ${REDIS_PORT:-6379} -a $REDIS_PASSWORD ping 2>/dev/null | grep -q PONG; then
        echo -e "${GREEN}✓ Redis connection OK${NC}"
    else
        echo -e "${RED}✗ Redis connection FAILED${NC}"
    fi
else
    echo -e "${RED}✗ Redis container not found${NC}"
fi

echo -e "\n${YELLOW}5. n8n-mcp Logs (last 20 lines)${NC}"
docker service logs --tail 20 n8n_n8n-mcp 2>&1 || echo "Service not running"

echo -e "\n${YELLOW}6. n8n-worker Logs (last 20 lines)${NC}"
docker service logs --tail 20 n8n_n8n-worker 2>&1 || echo "Service not running"

echo -e "\n${YELLOW}7. Environment Variables Check${NC}"
echo "  POSTGRES_USER: ${POSTGRES_USER}"
echo "  POSTGRES_DB: ${POSTGRES_DB}"
echo "  POSTGRES_PASSWORD: $([ -n "$POSTGRES_PASSWORD" ] && echo '[SET]' || echo '[NOT SET]')"
echo "  REDIS_PASSWORD: $([ -n "$REDIS_PASSWORD" ] && echo '[SET]' || echo '[NOT SET]')"
echo "  N8N_ENCRYPTION_KEY: $([ -n "$N8N_ENCRYPTION_KEY" ] && echo '[SET]' || echo '[NOT SET]')"
echo "  N8N_HOST: ${N8N_HOST}"

echo -e "\n${YELLOW}8. Network Check${NC}"
docker network inspect n8n_n8n-network --format '{{.Name}}: {{len .Containers}} containers' 2>/dev/null || echo "Network not found"

echo -e "\n${YELLOW}9. Node Configuration${NC}"
docker node ls
echo ""
echo "Manager nodes: $(docker node ls --filter 'role=manager' --format '{{.Hostname}}' | wc -l)"
echo "Worker nodes: $(docker node ls --filter 'role=worker' --format '{{.Hostname}}' | wc -l)"

echo -e "\n=========================================="
echo "Common Issues & Solutions"
echo "=========================================="
echo "1. n8n-mcp DB auth failed:"
echo "   → Password mismatch. Run: ./fix-deployment.sh"
echo ""
echo "2. n8n-worker 0/0 replicas:"
echo "   → No worker nodes (OrbStack single node)"
echo "   → Use docker-stack.orbstack.yml instead"
echo ""
echo "3. Services stuck in 'Starting':"
echo "   → Check logs: docker service logs n8n_<service>"
echo "   → Check dependencies: postgres & redis must be healthy first"
