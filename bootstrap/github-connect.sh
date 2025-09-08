#!/bin/bash
# GitHub Connection Script for Brewnix GitOps
# This script connects the bootstrapped system to GitHub for GitOps deployment

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

# Load environment variables
if [[ -f /opt/proxmox-firewall-bootstrap/.env ]]; then
    source /opt/proxmox-firewall-bootstrap/.env
else
    log_error "Bootstrap environment not found. Run usb-bootstrap.sh first."
    exit 1
fi

log_info "Starting GitHub connection for Proxmox Firewall GitOps"

# Check SSH key
if [[ ! -f /root/.ssh/id_ed25519 ]]; then
    log_error "SSH key not found. Run usb-bootstrap.sh first."
    exit 1
fi

# Test GitHub SSH connection
log_step "Testing GitHub SSH connection..."
if ! ssh -T git@github.com -o StrictHostKeyChecking=no 2>/dev/null; then
    log_error "SSH connection to GitHub failed. Please ensure:"
    log_error "1. The SSH public key has been added to your repository deploy keys"
    log_error "2. The deploy key has appropriate permissions"
    log_error ""
    log_info "SSH public key:"
    cat /root/.ssh/id_ed25519.pub
    exit 1
fi

log_info "SSH connection to GitHub successful!"

# Clone the GitOps repository
log_step "Cloning GitOps repository..."
cd /opt
if [[ -d proxmox-firewall-deployment ]]; then
    log_warn "Repository already exists. Pulling latest changes..."
    cd proxmox-firewall-deployment
    git pull origin $GITHUB_BRANCH
else
    log_info "Cloning repository: $GITHUB_REPO"
    git clone git@github.com:$GITHUB_REPO.git proxmox-firewall-deployment
    cd proxmox-firewall-deployment
fi

# Initialize submodules
log_step "Initializing submodules..."
git submodule update --init --recursive

# Setup git-crypt if available
if [[ -f .gitattributes ]] && command -v git-crypt &> /dev/null; then
    log_step "Setting up git-crypt..."
    if [[ ! -f .git/git-crypt/keys/default ]]; then
        log_warn "git-crypt key not found. You'll need to unlock secrets manually."
        log_warn "Run: git-crypt unlock /path/to/git-crypt-key"
    else
        log_info "git-crypt already configured"
    fi
fi

# Create site-specific SSH keys
log_step "Setting up site-specific SSH keys..."
mkdir -p /root/.ssh/sites

# Generate site-specific keys for deployment
if [[ ! -f /root/.ssh/sites/deployment_key ]]; then
    ssh-keygen -t ed25519 -C "deployment@proxmox-firewall" -f /root/.ssh/sites/deployment_key -N ""
    log_info "Generated deployment SSH key"
    log_info "Add this key to your Proxmox host(s):"
    echo "----------------------------------------"
    cat /root/.ssh/sites/deployment_key.pub
    echo "----------------------------------------"
fi

# Configure SSH config for multiple sites
cat > /root/.ssh/config << EOF
# Proxmox Firewall GitOps SSH Config

# GitHub
Host github.com
    HostName github.com
    User git
    IdentityFile /root/.ssh/id_ed25519
    IdentitiesOnly yes

# Proxmox hosts
Host proxmox-*
    User root
    IdentityFile /root/.ssh/sites/deployment_key
    IdentitiesOnly yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

# Site-specific hosts
EOF

# Setup Ansible configuration
log_step "Setting up Ansible configuration..."
if [[ ! -f ansible.cfg ]]; then
    cat > ansible.cfg << EOF
[defaults]
inventory = ./inventory
remote_user = root
private_key_file = /root/.ssh/sites/deployment_key
host_key_checking = False
retry_files_enabled = False
gathering = smart
fact_caching = memory
stdout_callback = yaml
callback_whitelist = timer,profile_tasks

[inventory]
enable_plugins = yaml, ini, auto

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=no
EOF
fi

# Create inventory directory
mkdir -p inventory

# Setup cron job for automated updates
log_step "Setting up automated updates..."
cat > /etc/cron.d/proxmox-firewall-updates << EOF
# Proxmox Firewall GitOps - Automated Updates
# Run every 15 minutes to check for configuration updates
*/15 * * * * root cd /opt/proxmox-firewall-deployment && ./scripts/update-site.sh >> /var/log/proxmox-firewall-updates.log 2>&1
EOF

# Create log directory
mkdir -p /var/log/proxmox-firewall

log_info "GitHub connection setup complete!"
log_info ""
log_info "Next steps:"
log_info "1. Add the deployment SSH key above to your Proxmox hosts"
log_info "2. Run: ./scripts/deploy-site.sh <site_name> to deploy"
log_info "3. Monitor logs: tail -f /var/log/proxmox-firewall-updates.log"
log_info ""
log_warn "System will automatically check for updates every 15 minutes"
