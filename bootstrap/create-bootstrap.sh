#!/bin/bash
# Brewnix Universal Bootstrap Script
# Creates bootable USB drives for all supported server types

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
LOG_FILE="/var/log/brewnix-bootstrap.log"
exec > >(tee -a "$LOG_FILE") 2>&1

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

usage() {
    cat << EOF
Brewnix Universal Bootstrap Creator

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --site-config FILE    Path to site configuration YAML file
    --usb-device DEVICE   USB device path (e.g., /dev/sdb)
    --server-type TYPE    Server type (proxmox-nas, proxmox-firewall, k3s-cluster)
    --help               Show this help message

EXAMPLES:
    $0 --site-config /opt/brewnix/config/sites/home-lab.yml --usb-device /dev/sdb
    $0 --server-type proxmox-nas --usb-device /dev/sdc

SUPPORTED SERVER TYPES:
    - proxmox-nas: Proxmox VE with ZFS storage
    - proxmox-firewall: Proxmox firewall appliance
    - k3s-cluster: Kubernetes cluster with K3s

EOF
}

# Parse command line arguments
SITE_CONFIG=""
USB_DEVICE=""
SERVER_TYPE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --site-config)
            SITE_CONFIG="$2"
            shift 2
            ;;
        --usb-device)
            USB_DEVICE="$2"
            shift 2
            ;;
        --server-type)
            SERVER_TYPE="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate arguments
if [[ -z "$USB_DEVICE" ]]; then
    error "USB device not specified. Use --usb-device option."
    exit 1
fi

if [[ -z "$SITE_CONFIG" && -z "$SERVER_TYPE" ]]; then
    error "Either site config file or server type must be specified."
    exit 1
fi

# Load site configuration if provided
if [[ -n "$SITE_CONFIG" ]]; then
    if [[ ! -f "$SITE_CONFIG" ]]; then
        error "Site configuration file not found: $SITE_CONFIG"
        exit 1
    fi

    # Extract server type from config
    if command -v python3 &> /dev/null; then
        SERVER_TYPE=$(python3 -c "
import yaml
with open('$SITE_CONFIG', 'r') as f:
    config = yaml.safe_load(f)
print(config.get('server_type', 'unknown'))
")
    else
        # Fallback: try to extract with grep/sed
        SERVER_TYPE=$(grep -E '^server_type:' "$SITE_CONFIG" | sed 's/.*: //' | tr -d '"')
    fi

    if [[ -z "$SERVER_TYPE" || "$SERVER_TYPE" == "unknown" ]]; then
        error "Could not determine server type from config file"
        exit 1
    fi

    log "Loaded site configuration: $SITE_CONFIG"
    log "Server type: $SERVER_TYPE"
fi

# Validate USB device
if [[ ! -b "$USB_DEVICE" ]]; then
    error "Invalid USB device: $USB_DEVICE"
    exit 1
fi

# Check if device is mounted
if mount | grep -q "$USB_DEVICE"; then
    warn "USB device is mounted. Unmounting..."
    umount "${USB_DEVICE}"* 2>/dev/null || true
fi

# Confirm destructive operation
info "This will completely erase the USB device: $USB_DEVICE"
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    info "Operation cancelled."
    exit 0
fi

# Create bootstrap based on server type
case "$SERVER_TYPE" in
    "proxmox-nas")
        log "Creating Proxmox NAS bootstrap..."
        bash "$SCRIPT_DIR/create-nas-usb.sh" --site-config "$SITE_CONFIG" --usb-device "$USB_DEVICE"
        ;;
    "proxmox-firewall")
        log "Creating Proxmox Firewall bootstrap..."
        bash "$SCRIPT_DIR/create-firewall-usb.sh" --site-config "$SITE_CONFIG" --usb-device "$USB_DEVICE"
        ;;
    "k3s-cluster")
        log "Creating K3s Cluster bootstrap..."
        bash "$SCRIPT_DIR/create-k3s-usb.sh" --site-config "$SITE_CONFIG" --usb-device "$USB_DEVICE"
        ;;
    *)
        error "Unsupported server type: $SERVER_TYPE"
        info "Supported types: proxmox-nas, proxmox-firewall, k3s-cluster"
        exit 1
        ;;
esac

log "Bootstrap creation completed successfully!"
info "You can now boot from the USB device to install $SERVER_TYPE"
