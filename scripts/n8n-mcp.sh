#!/bin/bash
# Save this as: ~/n8n-mcp.sh
# Make executable: chmod +x ~/n8n-mcp.sh

# Explicitly use Node 22 from nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Switch to Node 22
nvm use 22 > /dev/null 2>&1

# Disable SSL verification for self-signed cert
export NODE_TLS_REJECT_UNAUTHORIZED=0

# Run mcp-remote
exec npx mcp-remote https://n8n.agentshq.net:8645/mcp/filesystem
