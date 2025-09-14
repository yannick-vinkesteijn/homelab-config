#!/bin/bash
set -euo pipefail

# === Configuration ===
ENV_FILE="/opt/homelab/.secrets/pia.env"
CONFIG_PATH="/opt/homelab/.secrets/pia.conf"
WORKDIR="/tmp/manual-connections"

# === Load secrets ===
if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ Missing env file: $ENV_FILE"
  exit 1
fi

source "$ENV_FILE"

# Check required vars
: "${PIA_USER:?PIA_USER not set in $ENV_FILE}"
: "${PIA_PASS:?PIA_PASS not set in $ENV_FILE}"
: "${PREFERRED_REGION:?PREFERRED_REGION not set in $ENV_FILE}"
: "${DIP_TOKEN:=none}"

# === Prepare workdir ===
rm -rf "$WORKDIR"
git clone --depth 1 https://github.com/pia-foss/manual-connections "$WORKDIR"
cd "$WORKDIR"

# === Run setup to generate config ===
sudo -E \
  PIA_USER="$PIA_USER" \
  PIA_PASS="$PIA_PASS" \
  PREFERRED_REGION="$PREFERRED_REGION" \
  DIP_TOKEN="$DIP_TOKEN" \
  DISABLE_IPV6="yes" \
  AUTOCONNECT="false" \
  PIA_PF="false" \
  PIA_DNS="true" \
  VPN_PROTOCOL="wireguard" \
  PIA_CONNECT="false" \
  PIA_CONF_PATH="$CONFIG_PATH" \
  ./run_setup.sh