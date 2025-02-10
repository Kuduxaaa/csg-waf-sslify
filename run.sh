#!/bin/bash

DB_HOST="DB_HOST"
DB_USER="DB_USER"
DB_PASS="DB_PASS"
DB_NAME="DB_NAME"

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

getSSL() {
    DOMAIN=$1
    echo "Working for $DOMAIN"
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

    FULLCHAIN=$(find /etc/letsencrypt/live/ -maxdepth 1 -type d -name "$DOMAIN*" -exec echo "{}/fullchain.pem" \; | head -n 1)
    PRIVKEY=$(find /etc/letsencrypt/live/ -maxdepth 1 -type d -name "$DOMAIN*" -exec echo "{}/privkey.pem" \; | head -n 1)
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
    scp -i "/root/.ssh/id_rsa_no_passphrase" "/opt/sslify/certs/$DOMAIN.pem" root@10.0.0.4:/etc/haproxy/certs/
}

echo "NICE" > /opt/sslify/main.log
QUERY="SELECT domain FROM websites WHERE is_verified=1;"
RESULT=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "$QUERY" --batch --skip-column-names)

echo "$RESULT" | while read -r domain; do
    PATH_OF_CERT="/opt/sslify/certs/$domain.pem"

    if [ ! -f $PATH_OF_CERT ]; then
        getSSL "$domain"
    fi
done
