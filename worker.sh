#!/bin/bash

# Directory to monitor
WATCH_DIR="/etc/haproxy/certs"

# Events to watch for (modify, create, delete, move)
EVENTS="modify,create,delete,move"

# Service to restart
SERVICE="haproxy"

# Install inotify-tools if not already installed
if ! command -v inotifywait &> /dev/null; then
    echo "Installing inotify-tools..."
    apt-get update && apt-get install -y inotify-tools
fi

# Monitor directory indefinitely
inotifywait -m -q -e "$EVENTS" --format "%w%f" "$WATCH_DIR" | while read FILE
do
    echo "Detected change in: $FILE"
    # Add slight delay to handle multiple simultaneous events
    sleep 1
    echo "Restarting $SERVICE..."
    systemctl restart "$SERVICE"
    echo "$SERVICE restarted at $(date)"
done
