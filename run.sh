#!/bin/bash

DOMAIN="seclab.ge"

sudo certbot certonly --manual \
    --non-interactive \
    --agree-tos \
    --preferred-challenges=dns \
    --manual-auth-hook "/opt/sslify/hooks/auth-hook.sh" \
    --manual-cleanup-hook "/opt/sslify/hooks/cleanup-hook.sh" \
    --manual-public-ip-logging-ok \
    --debug \
    -d $DOMAIN -v

sleep 2
echo "Creating pem file"

FULLCHAIN="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
PRIVKEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
CERT_OUTPUT="/opt/sslify/certs/$DOMAIN.pem"
REMOTE_SERVERS=("10.0.0.4" "10.0.0.8")
SSH_KEY="/root/.ssh/id_rsa_no_passphrase"

# Check if certificate files exist
if [ ! -f "$FULLCHAIN" ] || [ ! -f "$PRIVKEY" ]; then
  echo "Error: Certificate files not found for $DOMAIN."
  exit 0
fi

# Combine fullchain and private key
echo "Creating combined certificate for $DOMAIN..."
cat "$FULLCHAIN" "$PRIVKEY" > "$CERT_OUTPUT"

# Verify the combined certificate was created
if [ ! -f "$CERT_OUTPUT" ]; then
  echo "Error: Failed to create $CERT_OUTPUT."
  exit 0
fi

# Copy the certificate to remote servers
for SERVER in "${REMOTE_SERVERS[@]}"; do
  echo "Copying certificate to $SERVER..."
  scp -i "$SSH_KEY" "$CERT_OUTPUT" root@"$SERVER":/etc/haproxy/certs/

  # Verify the copy was successful
  if [ $? -eq 0 ]; then
    echo "Successfully copied certificate to $SERVER."
  else
    echo "Error: Failed to copy certificate to $SERVER."
    exit 0
  fi
done

echo "Certificate deployment completed successfully."
exit 0

scp -i "/root/.ssh/id_rsa_no_passphrase" "/opt/sslify/certs/$DOMAIN.pem" root@10.0.0.4:/etc/haproxy/certs/
