#!/bin/bash

# Create certificate configuration
cat > /tmp/cert.conf <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C = BD
ST = Dhaka
L = Narsingdi
O = AgentsHQ
CN = *.agentshq.net

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = *.agentshq.net
DNS.2 = agentshq.net
DNS.3 = n8n.agentshq.net
DNS.4 = grafana.agentshq.net
EOF

# Generate private key
openssl genrsa -out ./config/traefik/certs/wildcard_agentshq_net.key 2048

# Generate certificate
openssl req -new -x509 -days 365 \
  -key ./config/traefik/certs/wildcard_agentshq_net.key \
  -out ./config/traefik/certs/wildcard_agentshq_net.crt \
  -config /tmp/cert.conf \
  -extensions v3_req

# Verify the certificate
echo "=== Certificate Details ==="
openssl x509 -in ./config/traefik/certs/wildcard_agentshq_net.crt -text -noout | grep -A1 "Subject:"
echo ""
echo "=== Subject Alternative Names ==="
openssl x509 -in ./config/traefik/certs/wildcard_agentshq_net.crt -text -noout | grep -A5 "Subject Alternative Name"

# Set proper permissions
chmod 644 ./config/traefik/certs/wildcard_agentshq_net.crt
chmod 600 ./config/traefik/certs/wildcard_agentshq_net.key

echo ""
echo "✅ Certificate generated successfully!"
echo "Now update your dynamic.yml and restart Traefik"
