#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/ipv6_prefix_monitor.log"
STATEFILE="/var/lib/ipv6_prefix_monitor.last"
INTERFACE="wlp3s0"

mkdir -p "$(dirname "$STATEFILE")"

CURRENT_PREFIX=$(ip -6 addr show dev "$INTERFACE" scope global \
  | grep -v 'temporary' \
  | grep -oP 'inet6 \K([0-9a-f:]+)' \
  | cut -d: -f1-4 \
  | head -n 1)

PREVIOUS_PREFIX=""
[[ -f "$STATEFILE" ]] && PREVIOUS_PREFIX=$(cat "$STATEFILE")

if [[ "$CURRENT_PREFIX" != "$PREVIOUS_PREFIX" ]]; then
    echo "$(date): Prefix changed: $PREVIOUS_PREFIX -> $CURRENT_PREFIX" | tee -a "$LOGFILE"
    echo "$CURRENT_PREFIX" > "$STATEFILE"
else
    echo "$(date): No change. Current prefix is still $CURRENT_PREFIX" >> "$LOGFILE"
fi
