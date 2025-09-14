#!/bin/bash
set -e

echo "🔧 Setting up IPv6 prefix change monitor..."

# Paths
SCRIPT_PATH="/opt/homelab/scripts/detect_ipv6_prefix_change.sh"
LOGFILE="/var/log/ipv6_prefix_monitor.log"
STATEFILE="/var/lib/ipv6_prefix_monitor.last"
SERVICE_PATH="/etc/systemd/system/ipv6-prefix-monitor.service"
TIMER_PATH="/etc/systemd/system/ipv6-prefix-monitor.timer"

# Create script directory
mkdir -p "$(dirname "$SCRIPT_PATH")"
mkdir -p "$(dirname "$STATEFILE")"

# 1️⃣ Monitoring Script
cat > "$SCRIPT_PATH" << 'EOF'
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
EOF

chmod +x "$SCRIPT_PATH"

# 2️⃣ systemd Service
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Monitor IPv6 prefix and trigger actions on change
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH
EOF

# 3️⃣ systemd Timer
cat > "$TIMER_PATH" <<EOF
[Unit]
Description=Run IPv6 prefix monitor every 10 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=10min
Unit=ipv6-prefix-monitor.service

[Install]
WantedBy=timers.target
EOF

# 4️⃣ Enable & start
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now ipv6-prefix-monitor.timer

echo "✅ Setup complete!"
echo "Check logs with:"
echo "  journalctl -u ipv6-prefix-monitor.service"
echo "  cat $LOGFILE"