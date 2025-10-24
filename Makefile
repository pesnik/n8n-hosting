deploy-dev:
	# Load all variables into your current shell session
	export $(cat .env | grep -v '^#' | xargs)

	# Then deploy
	docker stack deploy -c docker-stack.dev.yml n8n
self-sign:
	# Create the certs directory
	mkdir -p config/traefik/certs

	# Generate self-signed wildcard certificate
	openssl req -x509 -newkey rsa:4096 \
	  -keyout config/traefik/certs/wildcard_agentshq_net.key \
	  -out config/traefik/certs/wildcard_agentshq_net.crt \
	  -days 365 -nodes \
	  -subj "/CN=*.agentshq.net" \
	  -addext "subjectAltName=DNS:*.agentshq.net,DNS:agentshq.net"

	# Set permissions
	chmod 644 config/traefik/certs/wildcard_agentshq_net.crt
	chmod 600 config/traefik/certs/wildcard_agentshq_net.key
