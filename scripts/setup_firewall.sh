#!/bin/bash
set -e

echo "==> Setting UFW defaults"
sudo ufw default deny incoming
sudo ufw default allow outgoing

echo "==> Allowing SSH (port 22)"
sudo ufw allow 22/tcp

echo "==> Allowing HTTP/HTTPS for Traefik"
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

echo "==> Enabling UFW"
sudo ufw --force enable

echo "==> Current firewall status:"
sudo ufw status verbose

echo "✔ UFW hardened successfully"