#!/bin/bash
set -eo pipefail

DOMAIN="$CERTBOT_DOMAIN"
ZONE_FILE="/etc/bind/zones/db.${DOMAIN}"
LOG_FILE="/var/log/sslify-cleanup.log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== $(date '+%F %T') Starting cleanup ==="
echo "Processing domain: $DOMAIN"

# Verify zone file exists
if [ ! -f "$ZONE_FILE" ]; then
  echo "Zone file $ZONE_FILE not found!" | tee -a "$LOG_FILE"
  exit 1
fi

# Remove TXT record
echo "Removing TXT record from $ZONE_FILE"
sed -i "/_acme-challenge.${DOMAIN}.\t300\tIN\tTXT/d" "$ZONE_FILE"

# Update serial using Unix timestamp
NEW_SERIAL=$(date +%s)
sed -i "s/; Serial.*/; Serial $NEW_SERIAL/" "$ZONE_FILE"

# Reload BIND
echo "Reloading BIND"
if ! /usr/sbin/rndc reload "$DOMAIN"; then
  echo "BIND reload failed! Check logs:"
  journalctl -u bind9 --since "1 minute ago" | tail -n 20
  exit 1
fi

echo "Cleanup completed successfully"
