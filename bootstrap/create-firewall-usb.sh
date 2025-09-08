#!/bin/bash
# Proxmox Firewall Bootstrap Creator
# Creates bootable USB drive for Proxmox Firewall installation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
LOG_FILE="/var/log/brewnix-firewall-bootstrap.log"
exec > >(tee -a "$LOG_FILE") 2>&1

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Default configuration
SITE_CONFIG=""
USB_DEVICE=""
PROXMOX_ISO_URL="https://enterprise.proxmox.com/iso/proxmox-ve_8.1-1.iso"

usage() {
    cat << EOF
Proxmox Firewall Bootstrap Creator

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --site-config FILE    Path to site configuration YAML file
    --usb-device DEVICE   USB device path (e.g., /dev/sdb)
    --iso-url URL         Proxmox ISO download URL
    --help               Show this help message

EXAMPLE:
    $0 --site-config /opt/brewnix/config/sites/firewall.yml --usb-device /dev/sdb

EOF
}

# Parse command line arguments
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
        --iso-url)
            PROXMOX_ISO_URL="$2"
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
    error "USB device not specified"
    exit 1
fi

if [[ -z "$SITE_CONFIG" ]]; then
    error "Site configuration file not specified"
    exit 1
fi

# Load site configuration
if [[ ! -f "$SITE_CONFIG" ]]; then
    error "Site configuration file not found: $SITE_CONFIG"
    exit 1
fi

log "Loading site configuration: $SITE_CONFIG"

# Extract configuration values
SITE_NAME=$(grep -E '^site_name:' "$SITE_CONFIG" | sed 's/.*: //' | tr -d '"')
NETWORK_VLAN=$(grep -E '^network:' "$SITE_CONFIG" -A 10 | grep -E 'vlan_id:' | sed 's/.*: //' | tr -d ' ')
NETWORK_RANGE=$(grep -E '^network:' "$SITE_CONFIG" -A 10 | grep -E 'ip_range:' | sed 's/.*: //' | tr -d '"')

# Extract firewall-specific configuration
INTERFACES=$(grep -E '^firewall:' "$SITE_CONFIG" -A 10 | grep -E 'interfaces:' | sed 's/.*: //' | tr -d '"[]')

log "Site: $SITE_NAME"
log "Network VLAN: $NETWORK_VLAN"
log "Network Range: $NETWORK_RANGE"
log "Interfaces: $INTERFACES"

# Validate USB device
if [[ ! -b "$USB_DEVICE" ]]; then
    error "Invalid USB device: $USB_DEVICE"
    exit 1
fi

# Get device size
DEVICE_SIZE=$(lsblk -b -n -o SIZE "$USB_DEVICE" | head -1)
DEVICE_SIZE_GB=$((DEVICE_SIZE / 1024 / 1024 / 1024))

if [[ $DEVICE_SIZE_GB -lt 8 ]]; then
    error "USB device too small. Need at least 8GB, got ${DEVICE_SIZE_GB}GB"
    exit 1
fi

log "USB Device: $USB_DEVICE (${DEVICE_SIZE_GB}GB)"

# Download Proxmox ISO if not present
ISO_FILE="/tmp/proxmox-ve.iso"
if [[ ! -f "$ISO_FILE" ]]; then
    log "Downloading Proxmox ISO..."
    if ! curl -L -o "$ISO_FILE" "$PROXMOX_ISO_URL"; then
        error "Failed to download Proxmox ISO"
        exit 1
    fi
fi

# Verify ISO size (should be > 1GB)
ISO_SIZE=$(stat -c%s "$ISO_FILE" 2>/dev/null || stat -f%z "$ISO_FILE" 2>/dev/null || echo "0")
if [[ $ISO_SIZE -lt 1000000000 ]]; then
    error "Downloaded ISO file seems too small: $ISO_SIZE bytes"
    exit 1
fi

log "Proxmox ISO ready: $(ls -lh "$ISO_FILE" | awk '{print $5}')"

# Create USB drive
log "Creating bootable USB drive..."

# Unmount any existing partitions
umount "${USB_DEVICE}"* 2>/dev/null || true

# Create partition table
log "Creating partition table..."
parted -s "$USB_DEVICE" mklabel msdos

# Create boot partition (EFI)
parted -s "$USB_DEVICE" mkpart primary fat32 1MiB 512MiB
parted -s "$USB_DEVICE" set 1 boot on

# Create root partition
parted -s "$USB_DEVICE" mkpart primary ext4 512MiB 100%

# Format partitions
log "Formatting partitions..."
mkfs.vfat -F 32 "${USB_DEVICE}1"
mkfs.ext4 "${USB_DEVICE}2"

# Mount partitions
BOOT_MOUNT="/mnt/boot"
ROOT_MOUNT="/mnt/root"

mkdir -p "$BOOT_MOUNT" "$ROOT_MOUNT"

mount "${USB_DEVICE}1" "$BOOT_MOUNT"
mount "${USB_DEVICE}2" "$ROOT_MOUNT"

# Copy Proxmox ISO content
log "Copying Proxmox ISO content..."
mkdir -p "$ROOT_MOUNT/proxmox"
mount -o loop "$ISO_FILE" /mnt/iso
cp -r /mnt/iso/* "$ROOT_MOUNT/proxmox/"
umount /mnt/iso

# Create boot configuration
log "Creating boot configuration..."

# Create GRUB configuration
mkdir -p "$BOOT_MOUNT/EFI/BOOT"
cat > "$BOOT_MOUNT/EFI/BOOT/grub.cfg" << EOF
set timeout=5
set default=0

menuentry "Proxmox VE Firewall Installation" {
    linux /proxmox/boot/linux26 initrd=/proxmox/boot/initrd.img \\
          console=tty0 console=ttyS0,115200 \\
          net.ifnames=0 biosdevname=0 \\
          proxmox-firewall=true \\
          site-config=/proxmox/site-config.yml
    initrd /proxmox/boot/initrd.img
}

menuentry "Proxmox VE (Debug Mode)" {
    linux /proxmox/boot/linux26 initrd=/proxmox/boot/initrd.img \\
          console=tty0 console=ttyS0,115200 \\
          net.ifnames=0 biosdevname=0 \\
          debug=true
    initrd /proxmox/boot/initrd.img
}
EOF

# Copy GRUB EFI binary
if [[ -f "/usr/lib/grub/x86_64-efi/grub.efi" ]]; then
    cp "/usr/lib/grub/x86_64-efi/grub.efi" "$BOOT_MOUNT/EFI/BOOT/bootx64.efi"
elif [[ -f "/usr/lib/grub/i386-pc/boot.img" ]]; then
    # Fallback to legacy boot
    grub-install --target=i386-pc --boot-directory="$BOOT_MOUNT" "$USB_DEVICE"
fi

# Create site configuration for installation
log "Creating site configuration for installation..."
cp "$SITE_CONFIG" "$ROOT_MOUNT/proxmox/site-config.yml"

# Create post-install script
cat > "$ROOT_MOUNT/proxmox/post-install.sh" << 'EOF'
#!/bin/bash
# Proxmox Firewall Post-Installation Script

set -e

# Load site configuration
SITE_CONFIG="/proxmox/site-config.yml"
if [[ -f "$SITE_CONFIG" ]]; then
    SITE_NAME=$(grep -E '^site_name:' "$SITE_CONFIG" | sed 's/.*: //' | tr -d '"')
    NETWORK_VLAN=$(grep -E '^network:' "$SITE_CONFIG" -A 10 | grep -E 'vlan_id:' | sed 's/.*: //' | tr -d ' ')
    NETWORK_RANGE=$(grep -E '^network:' "$SITE_CONFIG" -A 10 | grep -E 'ip_range:' | sed 's/.*: //' | tr -d '"')
    INTERFACES=$(grep -E '^firewall:' "$SITE_CONFIG" -A 10 | grep -E 'interfaces:' | sed 's/.*: //' | tr -d '"[]')
fi

# Configure network interfaces
cat > /etc/network/interfaces << NETCFG
auto lo
iface lo inet loopback

# Management interface
auto vmbr0
iface vmbr0 inet static
    address 192.168.1.1/24
    gateway 192.168.1.254
    bridge-ports none
    bridge-stp off
    bridge-fd 0

# Additional interfaces for firewall
NETCFG

# Add additional interfaces if specified
if [[ -n "$INTERFACES" ]]; then
    IFS=',' read -ra INTERFACE_ARRAY <<< "$INTERFACES"
    for i in "${!INTERFACE_ARRAY[@]}"; do
        interface=$(echo "${INTERFACE_ARRAY[$i]}" | xargs)
        if [[ $i -gt 0 ]]; then
            cat >> /etc/network/interfaces << NETCFG

auto vmbr$((i+1))
iface vmbr$((i+1)) inet manual
    bridge-ports $interface
    bridge-stp off
    bridge-fd 0
NETCFG
        fi
    done
fi

# Configure firewall rules
cat > /etc/pve/firewall/cluster.fw << FWRULES
[OPTIONS]
enable: 1

[RULES]
# Default policies
POLICY IN DROP
POLICY OUT ACCEPT
POLICY FORWARD DROP

# Allow SSH
IN SSH(ACCEPT) -i vmbr0

# Allow web interface
IN HTTPS(ACCEPT) -i vmbr0

# Allow ICMP
IN ICMP(ACCEPT)
FWRULES

# Set hostname
if [[ -n "$SITE_NAME" ]]; then
    hostnamectl set-hostname "firewall-$SITE_NAME"
fi

# Enable services
systemctl enable pve-firewall
systemctl enable ssh

echo "Proxmox Firewall installation completed!"
echo "Please reboot and access the web interface at https://$(hostname -I | awk '{print $1}'):8006"
EOF

chmod +x "$ROOT_MOUNT/proxmox/post-install.sh"

# Cleanup
log "Cleaning up..."
umount "$BOOT_MOUNT" "$ROOT_MOUNT"
rmdir "$BOOT_MOUNT" "$ROOT_MOUNT"

# Remove temporary ISO
rm -f "$ISO_FILE"

log "Proxmox Firewall bootstrap USB created successfully!"
info "Insert the USB drive into your server and boot from it to begin installation."
info "The system will automatically configure firewall settings based on your site configuration."
