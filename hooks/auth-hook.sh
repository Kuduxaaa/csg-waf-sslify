#!/bin/bash
set -eo pipefail

DOMAIN="$CERTBOT_DOMAIN"
TOKEN="$CERTBOT_VALIDATION"
ZONE_FILE="/etc/bind/zones/db.${DOMAIN}"
LOG_FILE="/var/log/sslify-auth.log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== $(date '+%F %T') Starting auth hook ==="
echo "Domain: $DOMAIN | Token: $TOKEN"

# Validate input
[ -z "$DOMAIN" ] && { echo "Missing domain!"; exit 1; }
[ -z "$TOKEN" ] && { echo "Missing token!"; exit 1; }

# Add TXT record
echo "Adding TXT record to $ZONE_FILE"
printf "_acme-challenge.%s.\t300\tIN\tTXT\t\"%s\"\n" "$DOMAIN" "$TOKEN" >> "$ZONE_FILE"

# Update serial using Unix timestamp
NEW_SERIAL=$(date +%s)
sed -i "s/; Serial.*/; Serial $NEW_SERIAL/" "$ZONE_FILE"

# Reload BIND and verify
echo "Reloading BIND"
if ! /usr/sbin/rndc reload "$DOMAIN"; then
  echo "BIND reload failed! Check logs:"
  journalctl -u bind9 --since "1 minute ago" | tail -n 20
  exit 1
fi

# Wait for local DNS update
echo "Checking local DNS (retries: 20)"
for i in {1..20}; do
  if dig +short @127.0.0.1 TXT "_acme-challenge.$DOMAIN" | grep -q "$TOKEN"; then
    echo "Local DNS verified in attempt $i"
    break
  fi
  sleep 5
done

# Verify external propagation
echo "Checking public DNS (retries: 30)"
for i in {1..30}; do
  if dig +short @8.8.8.8 TXT "_acme-challenge.$DOMAIN" | grep -q "$TOKEN"; then
    echo "Public DNS verified in attempt $i"
    exit 0
  fi
  sleep 10
done

echo "DNS propagation timeout!"
exit 1
