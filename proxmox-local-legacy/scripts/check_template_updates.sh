#!/bin/bash
set -euo pipefail

# Load current versions
source "$(dirname "$0")/versions.yml"

# Function to get latest Ubuntu version
get_latest_ubuntu() {
    local current_version="$1"
    local latest_version
    latest_version=$(curl -s https://cloud-images.ubuntu.com/releases/ | grep -oP 'href="\K[0-9]+\.[0-9]+' | sort -V | tail -n1)

    if [ "$latest_version" != "$current_version" ]; then
        echo "$latest_version"
    else
        echo ""
    fi
}

# Function to get latest OPNsense version
get_latest_opnsense() {
    local current_version="$1"
    local latest_version
    latest_version=$(curl -s https://pkg.opnsense.org/releases/ | grep -oP 'href="\K[0-9]+\.[0-9]+' | sort -V | tail -n1)

    if [ "$latest_version" != "$current_version" ]; then
        echo "$latest_version"
    else
        echo ""
    fi
}

# Check for updates
ubuntu_update=$(get_latest_ubuntu "$UBUNTU_VERSION")
opnsense_update=$(get_latest_opnsense "$OPNSENSE_VERSION")

# Update versions.yml if needed
if [ -n "$ubuntu_update" ] || [ -n "$opnsense_update" ]; then
    echo "Updates available:"
    [ -n "$ubuntu_update" ] && echo "Ubuntu: $UBUNTU_VERSION -> $ubuntu_update"
    [ -n "$opnsense_update" ] && echo "OPNsense: $OPNSENSE_VERSION -> $opnsense_update"

    # Create backup of current versions
    cp "$(dirname "$0")/versions.yml" "$(dirname "$0")/versions.yml.bak"

    # Update versions.yml
    if [ -n "$ubuntu_update" ]; then
        sed -i "s/UBUNTU_VERSION=.*/UBUNTU_VERSION=$ubuntu_update/" "$(dirname "$0")/versions.yml"
    fi

    if [ -n "$opnsense_update" ]; then
        sed -i "s/OPNSENSE_VERSION=.*/OPNSENSE_VERSION=$opnsense_update/" "$(dirname "$0")/versions.yml"
    fi

    echo "Updated versions.yml"
    exit 0
else
    echo "No updates available"
    exit 1
fi
