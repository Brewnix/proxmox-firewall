#!/bin/bash
set -e

# Update system
apt update && apt upgrade -y

# Install dependencies
apt install -y openjdk-17-jdk-headless curl wget jsvc mongodb

# Resolve full CDN URL (TP-Link publishes direct https://static.tp-link.com/upload/software/.../*.deb
# links; there is no apt repo at repo.tp-link.com). Filenames may be omada_v* or Omada_Network_Application_v*.
PAGE='https://www.tp-link.com/us/support/download/omada-software-controller/'
HTML=$(curl -fsSL -A 'Mozilla/5.0' "$PAGE")
OMADA_URL=$(echo "$HTML" | grep -oE 'https://static\.tp-link\.com/upload/[^"]+\.deb' | head -n 1)
test -n "$OMADA_URL"
OMADA_DEB=$(basename "$OMADA_URL")
OMADA_VER=$(echo "$OMADA_DEB" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || echo unknown)

echo "Installing Omada Controller (${OMADA_VER}) from ${OMADA_URL}"

# Download and install Omada
cd /tmp
wget "$OMADA_URL"
dpkg -i ${OMADA_DEB} || true
apt -f install -y

# Enable and start the service
systemctl enable omada
systemctl start omada

echo "Omada Controller installed and started!"
