#!/bin/bash

set -euo pipefail

# Config
LOGFILE="/var/log/update_pihole_ipv6.log"
STATEFILE="/var/lib/pihole_ipv6.last"
INTERFACE="wlp3s0"
CONTAINER="pihole"
TOML_PATH="/etc/pihole/pihole.toml"

# Create state dir
mkdir -p "$(dirname "$STATEFILE")"

# Get current IPv6 address (non-temporary)
CURRENT_ADDR=$(ip -6 addr show dev "$INTERFACE" scope global \
  | grep -v 'temporary' | grep inet6 | awk '{print $2}' | cut -d/ -f1 | head -n1)

# Read previous from statefile
PREVIOUS_ADDR=""
[[ -f "$STATEFILE" ]] && PREVIOUS_ADDR=$(<"$STATEFILE")

# Compare and update if needed
if [[ "$CURRENT_ADDR" != "$PREVIOUS_ADDR" ]]; then
    echo "$(date): IPv6 changed: $PREVIOUS_ADDR -> $CURRENT_ADDR" >> "$LOGFILE"
    echo "$CURRENT_ADDR" > "$STATEFILE"

    # Update inside the container
    docker exec "$CONTAINER" bash -c "sed -i '/^IPV6_ADDRESS/d' $TOML_PATH && echo 'IPV6_ADDRESS = \"$CURRENT_ADDR\"' >> $TOML_PATH"
    docker restart "$CONTAINER"

    echo "$(date): Updated Pi-hole config and restarted DNS" >> "$LOGFILE"
else
    echo "$(date): No change. Current address: $CURRENT_ADDR" >> "$LOGFILE"
fi