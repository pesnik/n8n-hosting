#!/bin/bash
# Traefik Debugging Script for Docker Swarm (macOS compatible)

echo "=================================="
echo "Traefik Diagnostic Report (macOS)"
echo "=================================="
echo ""

echo "1. Checking Traefik service status..."
docker service ps n8n_traefik --no-trunc
echo ""

echo "2. Checking Traefik logs (last 100 lines)..."
docker service logs n8n_traefik --tail 100 2>&1
echo ""

echo "3. Checking if config files exist..."
echo "traefik.yml:"
if [ -f "./config/traefik/traefik.yml" ]; then
    echo "✓ Found"
    ls -lh ./config/traefik/traefik.yml
    echo "Content preview:"
    head -20 ./config/traefik/traefik.yml
else
    echo "✗ NOT FOUND"
fi

echo ""
echo "dynamic.yml:"
if [ -f "./config/traefik/dynamic.yml" ]; then
    echo "✓ Found"
    ls -lh ./config/traefik/dynamic.yml
else
    echo "✗ NOT FOUND"
fi

echo ""
echo "4. Checking certificates..."
if [ -d "./config/traefik/certs" ]; then
    echo "✓ Certs directory exists"
    ls -lh ./config/traefik/certs/
    echo ""
    echo "Certificate details:"
    for cert in ./config/traefik/certs/*.pem; do
        if [[ "$cert" != *"-key.pem" ]]; then
            echo "Checking: $cert"
            openssl x509 -in "$cert" -noout -subject -dates 2>/dev/null || echo "Failed to read certificate"
        fi
    done
else
    echo "✗ Certs directory NOT FOUND"
fi

echo ""
echo "5. Validating YAML syntax..."
echo "Checking traefik.yml..."
python3 -c "import yaml; yaml.safe_load(open('./config/traefik/traefik.yml'))" 2>&1 && echo "✓ Valid YAML" || echo "✗ Invalid YAML"

echo ""
echo "Checking dynamic.yml..."
python3 -c "import yaml; yaml.safe_load(open('./config/traefik/dynamic.yml'))" 2>&1 && echo "✓ Valid YAML" || echo "✗ Invalid YAML"

echo ""
echo "6. Checking network..."
docker network inspect n8n-network --format '{{json .}}' | python3 -m json.tool 2>/dev/null || docker network inspect n8n-network

echo ""
echo "7. Checking if ports are available (macOS)..."
for port in 80 443 8080; do
    if lsof -nP -iTCP:$port -sTCP:LISTEN 2>/dev/null; then
        echo "Port $port: ✗ ALREADY IN USE"
    else
        echo "Port $port: ✓ Available"
    fi
done

echo ""
echo "8. Checking Docker socket..."
ls -l /var/run/docker.sock 2>/dev/null || echo "Docker socket not found at standard location"

echo ""
echo "9. Testing Traefik config syntax..."
echo "Creating temporary container to validate config..."
docker run --rm -v $(pwd)/config/traefik/traefik.yml:/traefik.yml:ro \
    traefik:v3.5.3 \
    traefik --configFile=/traefik.yml --validateConfig 2>&1 || echo "Config validation failed"

echo ""
echo "10. Checking Swarm status..."
docker info | grep -A 5 "Swarm:"

echo ""
echo "=================================="
echo "Diagnostic Complete"
echo "=================================="
echo ""
echo "Next steps:"
echo "1. Check the logs above for error messages"
echo "2. Verify certificate paths are correct"
echo "3. Ensure no port conflicts"
echo "4. Validate YAML syntax is correct"
