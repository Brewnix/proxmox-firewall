#!/bin/bash
# Initial Configuration Script for Brewnix GitOps
# This script configures the basic system settings for deployment

set -e

#SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

log_info "Starting initial configuration for Proxmox Firewall"

# Load environment variables
if [[ -f /opt/proxmox-firewall-bootstrap/.env ]]; then
    source /opt/proxmox-firewall-bootstrap/.env
else
    log_error "Bootstrap environment not found. Run usb-bootstrap.sh first."
    exit 1
fi

# Configure hostname
log_step "Configuring system hostname..."
hostnamectl set-hostname "proxmox-bootstrap"

# Configure timezone
log_step "Configuring timezone..."
timedatectl set-timezone America/New_York  # Change as needed

# Configure network (DHCP for initial setup)
log_step "Configuring network..."
cat > /etc/netplan/01-netcfg.yaml << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: true
EOF

netplan apply

# Wait for network
log_info "Waiting for network connectivity..."
timeout=60
while ! ping -c 1 8.8.8.8 &>/dev/null; do
    if [[ $timeout -le 0 ]]; then
        log_error "Network connectivity timeout"
        exit 1
    fi
    sleep 5
    timeout=$((timeout - 5))
    log_info "Still waiting for network... ($timeout seconds remaining)"
done

log_info "Network connectivity established"

# Update system
log_step "Updating system packages..."
apt update
apt upgrade -y

# Install additional required packages
log_step "Installing additional packages..."
apt install -y \
    vim \
    htop \
    tmux \
    curl \
    wget \
    git \
    jq \
    unzip \
    python3 \
    python3-pip \
    python3-venv \
    ansible \
    terraform \
    git-crypt \
    age \
    sshpass \
    rsync

# Configure SSH
log_step "Configuring SSH..."
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl reload ssh

# Setup firewall (basic)
log_step "Setting up basic firewall..."
ufw --force enable
ufw allow ssh
ufw allow 80
ufw allow 443

# Create deployment directories
log_step "Creating deployment directories..."
mkdir -p /opt/proxmox-firewall
mkdir -p /var/log/proxmox-firewall
mkdir -p /var/backup/proxmox-firewall

# Setup logging
log_step "Setting up logging..."
cat > /etc/rsyslog.d/proxmox-firewall.conf << EOF
# Proxmox Firewall GitOps Logging
local0.* /var/log/proxmox-firewall/deployment.log
local1.* /var/log/proxmox-firewall/ansible.log
local2.* /var/log/proxmox-firewall/terraform.log
EOF

systemctl restart rsyslog

# Setup log rotation
cat > /etc/logrotate.d/proxmox-firewall << EOF
/var/log/proxmox-firewall/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 root root
    postrotate
        systemctl reload rsyslog
    endscript
}
EOF

# Create deployment user (optional, for security)
log_step "Setting up deployment user..."
if ! id -u deploy &>/dev/null; then
    useradd -m -s /bin/bash deploy
    usermod -aG sudo deploy
    mkdir -p /home/deploy/.ssh
    chmod 700 /home/deploy/.ssh
    cp /root/.ssh/authorized_keys /home/deploy/.ssh/ 2>/dev/null || true
    chown -R deploy:deploy /home/deploy/.ssh
    echo "deploy ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/deploy
fi

# Setup monitoring (basic)
log_step "Setting up basic monitoring..."
cat > /etc/cron.d/system-monitoring << EOF
# System monitoring for Proxmox Firewall
*/5 * * * * root /opt/proxmox-firewall-bootstrap/scripts/health-check.sh >> /var/log/proxmox-firewall/health.log 2>&1
EOF

# Create health check script
mkdir -p /opt/proxmox-firewall-bootstrap/scripts
cat > /opt/proxmox-firewall-bootstrap/scripts/health-check.sh << 'EOF'
#!/bin/bash
# Basic health check script
echo "$(date): System health check"
echo "Uptime: $(uptime)"
echo "Disk usage:"
df -h /
echo "Memory usage:"
free -h
echo "Network interfaces:"
ip addr show
echo "---"
EOF
chmod +x /opt/proxmox-firewall-bootstrap/scripts/health-check.sh

# Setup automatic cleanup
log_step "Setting up automatic cleanup..."
cat > /etc/cron.d/system-cleanup << EOF
# System cleanup for Proxmox Firewall
0 2 * * * root /opt/proxmox-firewall-bootstrap/scripts/cleanup.sh >> /var/log/proxmox-firewall/cleanup.log 2>&1
EOF

# Create cleanup script
cat > /opt/proxmox-firewall-bootstrap/scripts/cleanup.sh << 'EOF'
#!/bin/bash
# System cleanup script
echo "$(date): Running system cleanup"

# Clean package cache
apt autoremove -y
apt autoclean -y

# Clean old logs
find /var/log -name "*.gz" -type f -mtime +30 -delete
find /var/log -name "*.log.*" -type f -mtime +30 -delete

# Clean temp files
find /tmp -type f -mtime +7 -delete

echo "Cleanup completed"
EOF
chmod +x /opt/proxmox-firewall-bootstrap/scripts/cleanup.sh

# Final system info
log_info "Initial configuration complete!"
log_info ""
log_info "System Information:"
log_info "Hostname: $(hostname)"
log_info "IP Address: $(hostname -I | awk '{print $1}')"
log_info "SSH Key Fingerprint: $(ssh-keygen -l -f /root/.ssh/id_ed25519.pub)"
log_info ""
log_info "Next steps:"
log_info "1. Connect to GitHub: ./github-connect.sh"
log_info "2. Configure your sites in /opt/proxmox-firewall-deployment/sites/"
log_info "3. Deploy: ./scripts/deploy-site.sh <site_name>"
log_info ""
log_warn "Don't forget to change the default SSH keys for production use!"
