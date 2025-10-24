# Add certificate to macOS system keychain
sudo security add-trusted-cert -d -r trustRoot \
     -k /Library/Keychains/System.keychain \
     ./config/traefik/certs/wildcard_agentshq_net.crt

# Verify it was added
security find-certificate -c "agentshq.net" /Library/Keychains/System.keychain

