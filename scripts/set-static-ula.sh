#!/bin/bash
set -e

INTERFACE="wlp3s0"
STATIC_IPV6="fd00::53/64"

echo "🔍 Checking existing global IPv6 addresses on ${INTERFACE}:"
ip -6 addr show dev "$INTERFACE" scope global | grep inet6 || echo "No global IPv6 found."

echo
echo "➕ Adding ULA ${STATIC_IPV6} to ${INTERFACE} if not present..."
if ! ip -6 addr show dev "$INTERFACE" | grep -q "${STATIC_IPV6%/*}"; then
  sudo ip -6 addr add "$STATIC_IPV6" dev "$INTERFACE"
  echo "✅ ULA address added."
else
  echo "✅ Already present."
fi

echo
echo "🔁 Current IPv6 addresses on ${INTERFACE}:"
ip -6 addr show dev "$INTERFACE"