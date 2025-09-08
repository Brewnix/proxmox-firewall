#!/bin/bash
set -e

# Update system
apt update && apt upgrade -y

# Install dependencies
apt install -y openjdk-17-jdk-headless curl wget jsvc mongodb

# Get latest Omada version and hash
OMADA_DEB=$(curl -s https://www.tp-link.com/us/support/download/omada-software-controller/ | grep -o 'omada_v[0-9.]*_linux_x64_[0-9]*.deb' | head -n 1)
OMADA_VER=$(echo $OMADA_DEB | grep -o 'omada_v[0-9.]*' | cut -d'_' -f2)

# Get the date-based path from the download page
OMADA_PATH=$(curl -s https://www.tp-link.com/us/support/download/omada-software-controller/ | grep -o 'software/[0-9]*/[0-9]*/[0-9]*' | head -n 1)

echo "Installing Omada Controller version $OMADA_VER"

# Download and install Omada
cd /tmp
wget "https://static.tp-link.com/upload/${OMADA_PATH}/${OMADA_DEB}"
dpkg -i ${OMADA_DEB} || true
apt -f install -y

# Enable and start the service
systemctl enable omada
systemctl start omada

echo "Omada Controller installed and started!"
