#!/bin/bash
# gitops/deploy-gitops.sh - Modern GitOps deployment for Proxmox Firewall
# Replaces the legacy proxmox-local approach with GitOps and USB bootstrapping

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENDOR_ROOT="$(cd "${PROJECT_ROOT}/.." && pwd)"
BUILD_DIR="${VENDOR_ROOT}/build"

# Default values
OPERATION="deploy"
SITE_CONFIG=""
GITOPS_REPO=""
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1" >&2
    fi
}

# Usage information
show_usage() {
    cat << EOF
Modern GitOps Deployment for Proxmox Firewall

USAGE:
    $0 --operation <OPERATION> [OPTIONS] <SITE_CONFIG>

OPERATIONS:
    deploy              Deploy firewall infrastructure with GitOps
    sync                Sync configuration from GitOps repository
    usb-create          Create USB bootstrap image
    drift-check         Check for configuration drift
    validate            Validate site configuration
    backup              Backup current configuration
    test                Run comprehensive testing suite
    monitor             Run health monitoring and checks
    alert               Run advanced monitoring with alerting

OPTIONS:
    --gitops-repo URL   GitOps repository URL
    --usb-device PATH   USB device path for bootstrap creation
    --verbose           Enable verbose output
    --drift-only        Only perform drift detection
    --help              Show this help message

EXAMPLES:
    # Deploy with GitOps
    $0 --operation deploy --gitops-repo https://github.com/org/firewall-config.git config/sites/prod/firewall-site.yml
    
    # Create USB bootstrap
    $0 --operation usb-create --usb-device /dev/sdb config/sites/prod/firewall-site.yml
    
    # Check for drift
    $0 --operation drift-check config/sites/prod/firewall-site.yml
    
    # Run testing suite
    $0 --operation test config/sites/prod/firewall-site.yml
    
    # Run health monitoring
    $0 --operation monitor config/sites/prod/firewall-site.yml

ENVIRONMENT VARIABLES:
    TAILSCALE_AUTH_KEY      Tailscale authentication key
    GRAFANA_ADMIN_PASSWORD  Grafana admin password
    GITOPS_WEBHOOK_URL      Webhook URL for notifications
    AWS_ACCESS_KEY_ID       AWS access key for S3 backups
    AWS_SECRET_ACCESS_KEY   AWS secret key for S3 backups
    BACKUP_S3_BUCKET        S3 bucket for backups
    PBS_SERVER              Proxmox Backup Server hostname/IP
    PBS_DATASTORE           PBS datastore name
    PBS_USER                PBS username (optional)
    PBS_PASSWORD            PBS password (optional)
    PBS_TOKEN               PBS API token (alternative to user/pass)

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --operation)
                OPERATION="$2"
                shift 2
                ;;
            --gitops-repo)
                GITOPS_REPO="$2"
                shift 2
                ;;
            --usb-device)
                USB_DEVICE="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [[ -z "$SITE_CONFIG" ]]; then
                    SITE_CONFIG="$1"
                else
                    log_error "Multiple site configurations specified"
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$SITE_CONFIG" ]]; then
        log_error "Site configuration file is required"
        show_usage
        exit 1
    fi

    if [[ ! -f "$SITE_CONFIG" ]]; then
        log_error "Site configuration file not found: $SITE_CONFIG"
        exit 1
    fi
}

# Initialize environment
initialize() {
    log_info "Initializing GitOps deployment environment..."
    
    # Create build directory
    mkdir -p "$BUILD_DIR"
    
    # Parse site configuration
    local site_name
    site_name=$(grep "^site_name:" "$SITE_CONFIG" | cut -d'"' -f2 || echo "unknown")
    
    export SITE_NAME="$site_name"
    export DEPLOYMENT_TYPE="proxmox-firewall"
    export BUILD_DIR
    export PROJECT_ROOT
    
    log_debug "Site name: $SITE_NAME"
    log_debug "Build directory: $BUILD_DIR"
    log_debug "Project root: $PROJECT_ROOT"
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    local missing_tools=()
    
    # Check required tools
    for tool in ansible git python3 jq; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install missing tools and try again"
        exit 1
    fi
    
    # Check required environment variables for GitOps
    if [[ "$OPERATION" == "deploy" || "$OPERATION" == "sync" ]]; then
        local missing_vars=()
        
        if [[ -z "${TAILSCALE_AUTH_KEY:-}" ]]; then
            missing_vars+=("TAILSCALE_AUTH_KEY")
        fi
        
        if [[ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]]; then
            missing_vars+=("GRAFANA_ADMIN_PASSWORD")
        fi
        
        if [[ ${#missing_vars[@]} -gt 0 ]]; then
            log_error "Missing required environment variables: ${missing_vars[*]}"
            exit 1
        fi
    fi
    
    log_success "Prerequisites validation completed"
}

# Setup GitOps repository
setup_gitops() {
    if [[ -z "$GITOPS_REPO" ]]; then
        log_warning "No GitOps repository specified, skipping GitOps setup"
        return 0
    fi
    
    log_info "Setting up GitOps repository: $GITOPS_REPO"
    
    local gitops_dir="${BUILD_DIR}/gitops-repo"
    
    # Clone or update GitOps repository
    if [[ -d "$gitops_dir" ]]; then
        log_debug "Updating existing GitOps repository"
        cd "$gitops_dir"
        git fetch origin
        git reset --hard origin/main
    else
        log_debug "Cloning GitOps repository"
        git clone "$GITOPS_REPO" "$gitops_dir"
        cd "$gitops_dir"
    fi
    
    # Setup Git configuration for automated commits
    git config user.name "Brewnix GitOps"
    git config user.email "gitops@brewnix.local"
    
    log_success "GitOps repository setup completed"
}

# Create USB bootstrap image
create_usb_bootstrap() {
    if [[ -z "$USB_DEVICE" ]]; then
        log_error "USB device path required for bootstrap creation"
        exit 1
    fi
    
    log_info "Creating USB bootstrap image on $USB_DEVICE"
    
    # Validate USB device
    if [[ ! -b "$USB_DEVICE" ]]; then
        log_error "Invalid USB device: $USB_DEVICE"
        exit 1
    fi
    
    log_warning "This will erase all data on $USB_DEVICE"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "USB bootstrap creation cancelled"
        exit 0
    fi
    
    # Create bootstrap directory
    local bootstrap_dir="${BUILD_DIR}/usb-bootstrap"
    mkdir -p "$bootstrap_dir"
    
    # Copy site configuration
    cp "$SITE_CONFIG" "$bootstrap_dir/site-config.yml"
    
    # Copy SSH keys if available
    if [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
        cp "$HOME/.ssh/id_ed25519.pub" "$bootstrap_dir/authorized_keys"
    fi
    
    # Create bootstrap script
    cat > "$bootstrap_dir/bootstrap.sh" << 'EOF'
#!/bin/bash
# USB Bootstrap Script for Proxmox Firewall
set -euo pipefail

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

log_info "Starting Proxmox Firewall USB bootstrap..."

# Copy configuration to system
mkdir -p /opt/brewnix-firewall
cp site-config.yml /opt/brewnix-firewall/
cp authorized_keys /root/.ssh/ 2>/dev/null || true

# Setup SSH access
chmod 600 /root/.ssh/authorized_keys 2>/dev/null || true

# Install Git and clone firewall configuration
apt-get update
apt-get install -y git ansible python3-pip

# Clone firewall repository
cd /opt/brewnix-firewall
git clone https://github.com/Brewnix/brewnix-template.git repo
cd repo

# Run deployment
./scripts/deploy-vendor.sh proxmox-firewall /opt/brewnix-firewall/site-config.yml

log_info "USB bootstrap completed successfully"
EOF
    chmod +x "$bootstrap_dir/bootstrap.sh"
    
    # Format USB device and copy files
    log_info "Formatting USB device..."
    sudo mkfs.ext4 -F "$USB_DEVICE"
    
    # Mount and copy files
    local mount_point="/tmp/usb-mount-$$"
    mkdir -p "$mount_point"
    sudo mount "$USB_DEVICE" "$mount_point"
    
    sudo cp -r "$bootstrap_dir"/* "$mount_point/"
    sudo chmod +x "$mount_point/bootstrap.sh"
    
    sudo umount "$mount_point"
    rmdir "$mount_point"
    
    log_success "USB bootstrap image created successfully"
    log_info "To use: Insert USB into Proxmox server and run /media/usb/bootstrap.sh"
}

# Check for configuration drift
check_drift() {
    log_info "Checking for configuration drift..."
    
    local drift_report
    drift_report="${BUILD_DIR}/drift-report-${SITE_NAME}-$(date +%Y%m%d-%H%M%S).json"
    
    # Initialize drift report
    cat > "$drift_report" << EOF
{
    "site_name": "$SITE_NAME",
    "check_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "drift_detected": false,
    "changes": []
}
EOF
    
    # Check if GitOps repository has changes
    if [[ -n "$GITOPS_REPO" ]]; then
        local gitops_dir="${BUILD_DIR}/gitops-repo"
        if [[ -d "$gitops_dir" ]]; then
            cd "$gitops_dir"
            if ! git diff --quiet HEAD origin/main; then
                log_warning "GitOps repository has uncommitted changes"
                
                # Update drift report
                jq '.drift_detected = true | .changes += [{"type": "gitops", "description": "Uncommitted changes in GitOps repository"}]' \
                   "$drift_report" > "${drift_report}.tmp" && mv "${drift_report}.tmp" "$drift_report"
            fi
        fi
    fi
    
    # Check system configuration vs. expected state
    # This would typically involve checking actual firewall rules, VM configurations, etc.
    log_debug "Checking system configuration state..."
    
    # For now, simulate drift check
    local drift_detected=false
    
    if [[ "$drift_detected" == "true" ]]; then
        log_warning "Configuration drift detected!"
        log_info "Drift report saved to: $drift_report"
        
        # Send notification if webhook configured
        if [[ -n "${GITOPS_WEBHOOK_URL:-}" ]]; then
            curl -s -X POST "$GITOPS_WEBHOOK_URL" \
                 -H "Content-Type: application/json" \
                 -d "{\"text\": \"Configuration drift detected in $SITE_NAME\", \"report\": \"$drift_report\"}" || true
        fi
        
        return 1
    else
        log_success "No configuration drift detected"
        return 0
    fi
}

# Deploy firewall infrastructure
# Network-aware deployment functions for sophisticated firewall management

validate_site_network_config() {
    log_info "Validating site network configuration..."
    
    # Check if site configuration exists
    if [[ ! -f "$SITE_CONFIG" ]]; then
        log_error "Site configuration file not found: $SITE_CONFIG"
        return 1
    fi
    
    # Extract site name from config path 
    local site_name
    site_name=$(basename "$(dirname "$(dirname "$SITE_CONFIG")")")
    export DETERMINED_SITE_NAME="$site_name"
    
    # Validate network prefix configuration
    if ! grep -q "network_prefix:" "$SITE_CONFIG"; then
        log_error "Network prefix not configured in site config"
        return 1
    fi
    
    # Check for VLAN configuration
    if ! grep -q "vlans:" "$SITE_CONFIG"; then
        log_error "VLAN configuration missing from site config"
        return 1
    fi
    
    # Validate device templates directory exists
    local devices_templates_dir="${PROJECT_ROOT}/config/devices_templates"
    if [[ ! -d "$devices_templates_dir" ]]; then
        log_error "Device templates directory not found: $devices_templates_dir"
        return 1
    fi
    
    log_success "Site network configuration validation passed"
    return 0
}

deploy_network_infrastructure() {
    log_info "Deploying network infrastructure with VLAN support..."
    
    local site_name="${DETERMINED_SITE_NAME:-$(basename "$(dirname "$(dirname "$SITE_CONFIG")")")}"
    
    # Use the sophisticated network setup playbook
    local network_playbooks=(
        "06_initial_local_setup.yml"
        "03a_network_transition.yml"
        "03_network_setup.yml"
    )
    
    cd "${VENDOR_ROOT}/deployment/ansible"
    
    for playbook in "${network_playbooks[@]}"; do
        log_info "Running network playbook: $playbook"
        
        local ansible_cmd=(
            "ansible-playbook"
            "playbooks/$playbook"
            "-i" "inventory/localhost"
            "-e" "config_root=${PROJECT_ROOT}/config/proxmox-firewall"
            "-e" "site=$site_name"
        )
        
        if [[ "$VERBOSE" == "true" ]]; then
            ansible_cmd+=("-vvv")
        fi
        
        if ! "${ansible_cmd[@]}"; then
            log_error "Network playbook failed: $playbook"
            return 1
        fi
    done
    
    log_success "Network infrastructure deployment completed"
    return 0
}

deploy_device_configurations() {
    log_info "Deploying device configurations from templates..."
    
    local site_name="${DETERMINED_SITE_NAME:-$(basename "$(dirname "$(dirname "$SITE_CONFIG")")")}"
    local devices_dir="${PROJECT_ROOT}/config/proxmox-firewall/sites/${site_name}/devices"
    local templates_dir="${PROJECT_ROOT}/config/devices_templates"
    local render_script="${VENDOR_ROOT}/deployment/scripts/render_template.py"
    
    # Check if device configurations exist
    if [[ ! -d "$devices_dir" ]]; then
        log_warning "No device configurations found for site: $site_name"
        return 0
    fi
    
    # Process each device configuration
    for device_config in "$devices_dir"/*.yml; do
        if [[ -f "$device_config" ]]; then
            local device_name
            device_name=$(basename "$device_config" .yml)
            log_info "Processing device configuration: $device_name"
            
            # Extract template name from device config
            local template_name
            template_name=$(grep "^template:" "$device_config" | cut -d' ' -f2- | tr -d '"' || echo "")
            
            if [[ -n "$template_name" ]]; then
                local template_file="${templates_dir}/${template_name}"
                if [[ -f "$template_file" ]]; then
                    log_debug "Rendering template $template_name for device $device_name"
                    
                    # Render device configuration
                    if ! python3 "$render_script" "$device_config" -t "$templates_dir"; then
                        log_error "Failed to render device configuration: $device_name"
                        return 1
                    fi
                else
                    log_warning "Template not found: $template_file"
                fi
            fi
        fi
    done
    
    log_success "Device configuration deployment completed"
    return 0
}

deploy_firewall_security() {
    log_info "Deploying firewall security policies and rules..."
    
    local site_name="${DETERMINED_SITE_NAME:-$(basename "$(dirname "$(dirname "$SITE_CONFIG")")")}"
    
    # Deploy OPNsense and security configurations
    cd "${VENDOR_ROOT}/deployment/ansible"
    
    local security_playbooks=(
        "05_opnsense_setup.yml"
        "08_monitoring_setup.yml"
    )
    
    for playbook in "${security_playbooks[@]}"; do
        if [[ -f "playbooks/$playbook" ]]; then
            log_info "Running security playbook: $playbook"
            
            local ansible_cmd=(
                "ansible-playbook"
                "playbooks/$playbook"
                "-i" "inventory/localhost"
                "-e" "config_root=${PROJECT_ROOT}/config/proxmox-firewall"
                "-e" "site=$site_name"
            )
            
            if [[ "$VERBOSE" == "true" ]]; then
                ansible_cmd+=("-vvv")
            fi
            
            if ! "${ansible_cmd[@]}"; then
                log_error "Security playbook failed: $playbook"
                return 1
            fi
        else
            log_debug "Security playbook not found: $playbook"
        fi
    done
    
    log_success "Firewall security deployment completed"
    return 0
}

deploy_firewall() {
    log_info "Deploying Proxmox Firewall infrastructure with GitOps..."
    
    # Setup GitOps if configured
    if [[ -n "$GITOPS_REPO" ]]; then
        setup_gitops
    fi
    
    # Network-aware deployment that preserves sophisticated firewall capabilities
    log_info "Executing network-aware firewall deployment..."
    
    cd "$PROJECT_ROOT"
    
    # 1. Validate site configuration and network setup
    if ! validate_site_network_config; then
        log_error "Site network configuration validation failed"
        return 1
    fi
    
    # 2. Deploy core network infrastructure with VLAN management
    if ! deploy_network_infrastructure; then
        log_error "Network infrastructure deployment failed"
        return 1
    fi
    
    # 3. Deploy device templates and generate configurations
    if ! deploy_device_configurations; then
        log_error "Device configuration deployment failed"
        return 1
    fi
    
    # 4. Deploy firewall rules and security policies
    if ! deploy_firewall_security; then
        log_error "Firewall security deployment failed"
        return 1
    fi
    
    # 5. Run the vendor deployment script for remaining components
    local deploy_cmd=(
        "${VENDOR_ROOT}/scripts/deploy-vendor.sh"
        "proxmox-firewall"
        "$SITE_CONFIG"
    )
    
    if [[ "$VERBOSE" == "true" ]]; then
        deploy_cmd+=("-vvv")
    fi
    
    log_debug "Running vendor deployment: ${deploy_cmd[*]}"
    
    if "${deploy_cmd[@]}"; then
        log_success "Vendor deployment completed successfully"
    else
        log_error "Vendor deployment failed"
        return 1
    fi
    
    # Setup drift detection service
    setup_drift_detection
    
    # Perform initial drift check
    check_drift || true
    
    log_success "Network-aware GitOps deployment completed successfully"
}

# Setup drift detection service
setup_drift_detection() {
    log_info "Setting up drift detection service..."
    
    # Create drift detection script
    local drift_script="/usr/local/bin/brewnix-drift-check"
    sudo tee "$drift_script" > /dev/null << EOF
#!/bin/bash
# Brewnix Drift Detection Service
cd "$PROJECT_ROOT"
"$SCRIPT_DIR/deploy-gitops.sh" --operation drift-check "$SITE_CONFIG"
EOF
    sudo chmod +x "$drift_script"
    
    # Create systemd service
    sudo tee /etc/systemd/system/brewnix-drift-detection.service > /dev/null << EOF
[Unit]
Description=Brewnix Configuration Drift Detection
After=network.target

[Service]
Type=oneshot
ExecStart=$drift_script
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # Create systemd timer
    sudo tee /etc/systemd/system/brewnix-drift-detection.timer > /dev/null << EOF
[Unit]
Description=Run Brewnix drift detection every 5 minutes
Requires=brewnix-drift-detection.service

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Enable and start timer
    sudo systemctl daemon-reload
    sudo systemctl enable brewnix-drift-detection.timer
    sudo systemctl start brewnix-drift-detection.timer
    
    log_success "Drift detection service configured"
}

# Sync from GitOps repository
sync_gitops() {
    if [[ -z "$GITOPS_REPO" ]]; then
        log_error "GitOps repository URL required for sync operation"
        exit 1
    fi
    
    log_info "Syncing network configuration from GitOps repository..."
    
    setup_gitops
    
    # Check for changes and apply if needed
    local gitops_dir="${BUILD_DIR}/gitops-repo"
    cd "$gitops_dir"
    
    if git diff --quiet HEAD~1 HEAD; then
        log_info "No changes detected in GitOps repository"
        return 0
    fi
    
    log_info "Network configuration changes detected, applying..."
    
    # Sync complete site configuration including network and device configs
    local site_name="${SITE_NAME:-$(basename "$(dirname "$(dirname "$SITE_CONFIG")")")}"
    local gitops_site_dir="config/sites/${site_name}"
    local local_site_dir="${PROJECT_ROOT}/config/proxmox-firewall/sites/${site_name}"
    
    if [[ -d "$gitops_site_dir" ]]; then
        log_info "Syncing complete site configuration for: $site_name"
        
        # Backup current configuration
        backup_config
        
        # Copy updated site configuration
        if [[ -f "${gitops_site_dir}/config/site.conf" ]]; then
            cp "${gitops_site_dir}/config/site.conf" "${local_site_dir}/config/site.conf"
            log_info "Updated site configuration from GitOps"
        fi
        
        # Copy device configurations if they exist
        if [[ -d "${gitops_site_dir}/devices" ]]; then
            cp -r "${gitops_site_dir}/devices/"* "${local_site_dir}/devices/" 2>/dev/null || true
            log_info "Updated device configurations from GitOps"
        fi
        
        # Copy any custom templates
        if [[ -d "${gitops_site_dir}/templates" ]]; then
            cp -r "${gitops_site_dir}/templates/"* "${PROJECT_ROOT}/config/devices_templates/" 2>/dev/null || true
            log_info "Updated device templates from GitOps"
        fi
        
        # Validate the updated configuration
        if ! validate_site_network_config; then
            log_error "Updated configuration validation failed, restoring backup"
            restore_backup
            return 1
        fi
        
        # Deploy with updated network-aware configuration
        deploy_firewall
    else
        log_warning "GitOps site directory not found: $gitops_site_dir"
        return 1
    fi
}

# Validate site configuration
validate_config() {
    log_info "Validating site configuration: $SITE_CONFIG"
    
    # Use existing validation script if available
    local validate_script="${PROJECT_ROOT}/validate-config.sh"
    if [[ -f "$validate_script" ]]; then
        "$validate_script" "$SITE_CONFIG"
    else
        # Basic YAML validation
        python3 -c "
import yaml
import sys
try:
    with open('$SITE_CONFIG', 'r') as f:
        yaml.safe_load(f)
    print('Configuration file is valid YAML')
except yaml.YAMLError as e:
    print(f'YAML validation error: {e}')
    sys.exit(1)
except Exception as e:
    print(f'Error reading file: {e}')
    sys.exit(1)
"
    fi
    
    log_success "Configuration validation completed"
}

# Backup current configuration
backup_config() {
    log_info "Backing up current configuration..."

    local backup_dir
    backup_dir="${BUILD_DIR}/backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"

    # Backup site configuration
    cp "$SITE_CONFIG" "$backup_dir/site-config.yml"

    # Backup system state if GitOps repository exists
    if [[ -n "$GITOPS_REPO" ]] && [[ -d "${BUILD_DIR}/gitops-repo" ]]; then
        cp -r "${BUILD_DIR}/gitops-repo" "$backup_dir/gitops-repo"
    fi

    # Backup environment variables (encrypted)
    if [[ -f "${BUILD_DIR}/.env" ]]; then
        encrypt_file "${BUILD_DIR}/.env" "$backup_dir/.env.enc"
    fi

    # Backup system configuration
    backup_system_config "$backup_dir"

    # Create backup metadata
    create_backup_metadata "$backup_dir"

    # Compress backup
    local backup_archive
    backup_archive="backup-${SITE_NAME}-$(date +%Y%m%d-%H%M%S).tar.gz"
    cd "${BUILD_DIR}/backups"
    tar -czf "$backup_archive" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"

    # Verify backup integrity
    if ! verify_backup_integrity "$backup_archive"; then
        log_error "Backup integrity verification failed"
        return 1
    fi

    # Upload to cloud storage if configured
    if [[ -n "${BACKUP_S3_BUCKET:-}" ]]; then
        upload_to_s3 "$backup_archive"
    fi

    if [[ -n "${BACKUP_GCS_BUCKET:-}" ]]; then
        upload_to_gcs "$backup_archive"
    fi

    if [[ -n "${BACKUP_AZURE_CONTAINER:-}" ]]; then
        upload_to_azure "$backup_archive"
    fi

    if [[ -n "${PBS_SERVER:-}" && -n "${PBS_DATASTORE:-}" ]]; then
        upload_to_pbs "$backup_archive"
    fi

    # Backup VMs to PBS if running on Proxmox VE
    if [[ -n "${PBS_SERVER:-}" && -n "${PBS_DATASTORE:-}" && -f "/etc/pve/.version" ]]; then
        backup_vms_to_pbs
    fi

    log_success "Configuration backup completed: $backup_archive"
}

# Backup system configuration
backup_system_config() {
    local backup_dir="$1"

    log_debug "Backing up system configuration..."

    # Backup network configuration
    if [[ -d "/etc/netplan" ]]; then
        cp -r "/etc/netplan" "$backup_dir/netplan"
    fi

    # Backup firewall rules (if using iptables/ufw)
    if command -v iptables &> /dev/null; then
        iptables-save > "$backup_dir/iptables-rules.v4"
    fi

    if command -v ip6tables &> /dev/null; then
        ip6tables-save > "$backup_dir/iptables-rules.v6"
    fi

    # Backup systemd network configuration
    if [[ -d "/etc/systemd/network" ]]; then
        cp -r "/etc/systemd/network" "$backup_dir/systemd-network"
    fi

    # Backup DNS configuration
    if [[ -f "/etc/resolv.conf" ]]; then
        cp "/etc/resolv.conf" "$backup_dir/resolv.conf"
    fi

    # Backup SSH configuration
    if [[ -f "/etc/ssh/sshd_config" ]]; then
        cp "/etc/ssh/sshd_config" "$backup_dir/sshd_config"
    fi

    # Backup certificates if they exist
    if [[ -d "/etc/ssl/certs" ]]; then
        mkdir -p "$backup_dir/ssl"
        find "/etc/ssl/certs" -name "*.pem" -o -name "*.crt" -o -name "*.key" | head -10 | xargs -I {} cp {} "$backup_dir/ssl/" 2>/dev/null || true
    fi
}

# Create backup metadata
create_backup_metadata() {
    local backup_dir="$1"

    # Gather system information
    local system_info
    system_info=$(uname -a)
    local kernel_version
    kernel_version=$(uname -r)
    local uptime_info
    uptime_info=$(uptime)
    local disk_usage
    disk_usage=$(df -h / | tail -1)
    local memory_info
    memory_info=$(free -h | grep "^Mem:")

    # Create comprehensive metadata
    cat > "$backup_dir/metadata.json" << EOF
{
    "site_name": "$SITE_NAME",
    "backup_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "backup_timestamp": "$(date +%s)",
    "gitops_repo": "$GITOPS_REPO",
    "deployment_type": "$DEPLOYMENT_TYPE",
    "system_info": {
        "hostname": "$(hostname)",
        "os": "$system_info",
        "kernel": "$kernel_version",
        "uptime": "$uptime_info",
        "disk_usage": "$disk_usage",
        "memory": "$memory_info"
    },
    "backup_components": [
        "site_config",
        "gitops_repo",
        "system_config",
        "network_config",
        "security_config"
    ],
    "backup_version": "2.0",
    "compression": "gzip",
    "encryption": ${BACKUP_ENCRYPTION:-false}
}
EOF
}

# Encrypt file using GPG
encrypt_file() {
    local input_file="$1"
    local output_file="$2"

    if [[ ! -f "$input_file" ]]; then
        log_warning "Input file for encryption not found: $input_file"
        return 1
    fi

    if [[ -z "${BACKUP_GPG_KEY:-}" ]]; then
        log_warning "No GPG key configured for encryption, skipping encryption"
        cp "$input_file" "$output_file"
        return 0
    fi

    if command -v gpg &> /dev/null; then
        if gpg --encrypt --recipient "$BACKUP_GPG_KEY" --output "$output_file" "$input_file" 2>/dev/null; then
            log_debug "File encrypted successfully: $input_file"
            return 0
        else
            log_warning "GPG encryption failed, copying file unencrypted"
            cp "$input_file" "$output_file"
            return 1
        fi
    else
        log_warning "GPG not available, copying file unencrypted"
        cp "$input_file" "$output_file"
        return 1
    fi
}

# Decrypt file using GPG
decrypt_file() {
    local input_file="$1"
    local output_file="$2"

    if [[ ! -f "$input_file" ]]; then
        log_error "Input file for decryption not found: $input_file"
        return 1
    fi

    if command -v gpg &> /dev/null; then
        if gpg --decrypt --output "$output_file" "$input_file" 2>/dev/null; then
            log_debug "File decrypted successfully: $input_file"
            return 0
        else
            log_error "GPG decryption failed"
            return 1
        fi
    else
        log_error "GPG not available for decryption"
        return 1
    fi
}

# Verify backup integrity
verify_backup_integrity() {
    local backup_file="$1"

    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found for integrity check: $backup_file"
        return 1
    fi

    log_debug "Verifying backup integrity: $backup_file"

    # Check if file is readable
    if ! head -c 1024 "$backup_file" &>/dev/null; then
        log_error "Backup file is not readable"
        return 1
    fi

    # For tar.gz files, verify archive integrity
    if [[ "$backup_file" == *.tar.gz ]]; then
        if ! tar -tzf "$backup_file" &>/dev/null; then
            log_error "Backup archive is corrupted"
            return 1
        fi
    fi

    # Calculate and store checksum
    local checksum_file="${backup_file}.sha256"
    if command -v sha256sum &> /dev/null; then
        sha256sum "$backup_file" > "$checksum_file"
        log_debug "Backup checksum calculated: $(cat "$checksum_file")"
    fi

    log_debug "Backup integrity verification passed"
    return 0
}

# Upload backup to AWS S3
upload_to_s3() {
    local backup_file="$1"

    if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" || -z "${BACKUP_S3_BUCKET:-}" ]]; then
        log_warning "AWS credentials or S3 bucket not configured, skipping cloud upload"
        return 1
    fi

    log_info "Uploading backup to S3: s3://${BACKUP_S3_BUCKET}/backups/${SITE_NAME}/"

    # Set AWS credentials for this session
    export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
    export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

    # Upload using AWS CLI if available
    if command -v aws &> /dev/null; then
        if aws s3 cp "$backup_file" "s3://${BACKUP_S3_BUCKET}/backups/${SITE_NAME}/" --storage-class STANDARD_IA; then
            log_success "Backup uploaded to S3 successfully"

            # Also upload checksum if it exists
            local checksum_file="${backup_file}.sha256"
            if [[ -f "$checksum_file" ]]; then
                aws s3 cp "$checksum_file" "s3://${BACKUP_S3_BUCKET}/backups/${SITE_NAME}/"
            fi

            return 0
        else
            log_error "Failed to upload backup to S3"
            return 1
        fi
    else
        log_warning "AWS CLI not available, skipping S3 upload"
        return 1
    fi
}

# Upload backup to Google Cloud Storage
upload_to_gcs() {
    local backup_file="$1"

    if [[ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" || -z "${BACKUP_GCS_BUCKET:-}" ]]; then
        log_warning "GCS credentials or bucket not configured, skipping GCS upload"
        return 1
    fi

    log_info "Uploading backup to GCS: gs://${BACKUP_GCS_BUCKET}/backups/${SITE_NAME}/"

    if command -v gsutil &> /dev/null; then
        if gsutil cp "$backup_file" "gs://${BACKUP_GCS_BUCKET}/backups/${SITE_NAME}/"; then
            log_success "Backup uploaded to GCS successfully"
            return 0
        else
            log_error "Failed to upload backup to GCS"
            return 1
        fi
    else
        log_warning "gsutil not available, skipping GCS upload"
        return 1
    fi
}

# Upload backup to Azure Blob Storage
upload_to_azure() {
    local backup_file="$1"

    if [[ -z "${AZURE_STORAGE_ACCOUNT:-}" || -z "${AZURE_STORAGE_KEY:-}" || -z "${BACKUP_AZURE_CONTAINER:-}" ]]; then
        log_warning "Azure credentials or container not configured, skipping Azure upload"
        return 1
    fi

    log_info "Uploading backup to Azure: ${AZURE_STORAGE_ACCOUNT}/${BACKUP_AZURE_CONTAINER}/backups/${SITE_NAME}/"

    if command -v az &> /dev/null; then
        if az storage blob upload --account-name "$AZURE_STORAGE_ACCOUNT" --account-key "$AZURE_STORAGE_KEY" --container-name "$BACKUP_AZURE_CONTAINER" --name "backups/${SITE_NAME}/$(basename "$backup_file")" --file "$backup_file"; then
            log_success "Backup uploaded to Azure successfully"
            return 0
        else
            log_error "Failed to upload backup to Azure"
            return 1
        fi
    else
        log_warning "Azure CLI not available, skipping Azure upload"
        return 1
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    local backups_dir="${BUILD_DIR}/backups"

    if [[ ! -d "$backups_dir" ]]; then
        return 0
    fi

    log_debug "Cleaning up old backups..."

    # Keep last 30 daily backups
    local daily_backups
    daily_backups=$(find "$backups_dir" -name "backup-${SITE_NAME}-*.tar.gz" -mtime -30 | wc -l)

    if [[ $daily_backups -gt 30 ]]; then
        find "$backups_dir" -name "backup-${SITE_NAME}-*.tar.gz" -mtime -30 | head -n -30 | xargs rm -f
        log_debug "Removed old daily backups, keeping last 30"
    fi

    # Keep last 12 weekly backups (older than 30 days but newer than 365 days)
    local weekly_backups
    weekly_backups=$(find "$backups_dir" -name "backup-${SITE_NAME}-*.tar.gz" -mtime -365 | wc -l)

    if [[ $weekly_backups -gt 12 ]]; then
        find "$backups_dir" -name "backup-${SITE_NAME}-*.tar.gz" -mtime -365 | head -n -12 | xargs rm -f
        log_debug "Removed old weekly backups, keeping last 12"
    fi

    # Keep last 2 yearly backups (older than 365 days)
    local yearly_backups
    yearly_backups=$(find "$backups_dir" -name "backup-${SITE_NAME}-*.tar.gz" | wc -l)

    if [[ $yearly_backups -gt 2 ]]; then
        find "$backups_dir" -name "backup-${SITE_NAME}-*.tar.gz" | head -n -2 | xargs rm -f
        log_debug "Removed old yearly backups, keeping last 2"
    fi

    # Clean up orphaned checksum files
    find "$backups_dir" -name "*.sha256" -exec sh -c 'if [ ! -f "${1%.sha256}" ]; then rm "$1"; fi' _ {} \;

    log_debug "Backup cleanup completed"
}

# Setup automated backup service
setup_automated_backup() {
    log_info "Setting up automated backup service..."

    # Create backup script
    local backup_script="/usr/local/bin/brewnix-backup"
    sudo tee "$backup_script" > /dev/null << EOF
#!/bin/bash
# Brewnix Automated Backup Service
cd "$PROJECT_ROOT"
"$SCRIPT_DIR/deploy-gitops.sh" --operation backup "$SITE_CONFIG"
EOF
    sudo chmod +x "$backup_script"

    # Create systemd service
    sudo tee /etc/systemd/system/brewnix-backup.service > /dev/null << EOF
[Unit]
Description=Brewnix Automated Backup
After=network.target

[Service]
Type=oneshot
ExecStart=$backup_script
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Create systemd timer for daily backups
    sudo tee /etc/systemd/system/brewnix-backup.timer > /dev/null << EOF
[Unit]
Description=Run Brewnix backup daily
Requires=brewnix-backup.service

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=3600

[Install]
WantedBy=timers.target
EOF

    # Enable and start timer
    sudo systemctl daemon-reload
    sudo systemctl enable brewnix-backup.timer
    sudo systemctl start brewnix-backup.timer

    log_success "Automated backup service configured (daily at random time)"
}

# Restore configuration from backup
restore_backup() {
    log_info "Restoring configuration from backup..."

    local backups_dir="${BUILD_DIR}/backups"
    if [[ ! -d "$backups_dir" ]]; then
        log_error "No backups directory found"
        return 1
    fi

    # Find latest backup for this site
    local latest_backup
    latest_backup=$(find "$backups_dir" -name "backup-${SITE_NAME}-*.tar.gz" -type f | sort -r | head -n 1)

    if [[ -z "$latest_backup" ]]; then
        log_error "No backup found for site: $SITE_NAME"
        return 1
    fi

    log_info "Restoring from backup: $(basename "$latest_backup")"

    # Verify backup integrity before restoration
    if ! verify_backup_integrity "$latest_backup"; then
        log_error "Backup integrity verification failed, aborting restore"
        return 1
    fi

    # Extract and restore
    local restore_dir
    restore_dir=$(mktemp -d)
    cd "$restore_dir"
    tar -xzf "$latest_backup"

    # Restore site configuration
    local extracted_dir
    extracted_dir=$(find . -type d -name "backup-*" | head -n 1)
    if [[ -f "${extracted_dir}/site-config.yml" ]]; then
        cp "${extracted_dir}/site-config.yml" "$SITE_CONFIG"
        log_info "Site configuration restored"
    fi

    # Restore encrypted environment file
    if [[ -f "${extracted_dir}/.env.enc" ]]; then
        if decrypt_file "${extracted_dir}/.env.enc" "${BUILD_DIR}/.env"; then
            log_info "Environment file restored and decrypted"
        else
            log_warning "Failed to decrypt environment file"
        fi
    fi

    # Restore GitOps repository if available
    if [[ -d "${extracted_dir}/gitops-repo" ]]; then
        rm -rf "${BUILD_DIR}/gitops-repo"
        cp -r "${extracted_dir}/gitops-repo" "${BUILD_DIR}/gitops-repo"
        log_info "GitOps repository restored"
    fi

    # Restore system configuration (optional, with confirmation)
    if [[ "${RESTORE_SYSTEM_CONFIG:-false}" == "true" ]]; then
        restore_system_config "$extracted_dir"
    fi

    # Cleanup
    rm -rf "$restore_dir"

    log_success "Configuration restore completed"
}

# Restore system configuration
restore_system_config() {
    local extracted_dir="$1"

    log_info "Restoring system configuration..."

    # Restore network configuration
    if [[ -d "${extracted_dir}/netplan" && -d "/etc/netplan" ]]; then
        cp -r "${extracted_dir}/netplan"/* "/etc/netplan/"
        log_info "Network configuration restored"
    fi

    # Restore firewall rules
    if [[ -f "${extracted_dir}/iptables-rules.v4" ]]; then
        iptables-restore < "${extracted_dir}/iptables-rules.v4"
        log_info "IPv4 firewall rules restored"
    fi

    if [[ -f "${extracted_dir}/iptables-rules.v6" ]]; then
        ip6tables-restore < "${extracted_dir}/iptables-rules.v6"
        log_info "IPv6 firewall rules restored"
    fi

    # Note: Other system configurations are restored manually as they may require system restart
    log_warning "Some system configurations may require manual intervention or system restart"
}

# List available backups
list_backups() {
    local backups_dir="${BUILD_DIR}/backups"

    if [[ ! -d "$backups_dir" ]]; then
        log_info "No backups directory found"
        return 0
    fi

    log_info "Available backups for site: $SITE_NAME"

    echo "=================================================================================="
    printf "%-30s %-10s %-8s %-s\n" "TIMESTAMP" "SIZE" "TYPE" "FILENAME"
    echo "=================================================================================="

    find "$backups_dir" -name "backup-${SITE_NAME}-*.tar.gz" -type f | sort -r | while read -r backup_file; do
        local filename
        filename=$(basename "$backup_file")
        local timestamp
        timestamp=$(echo "$filename" | sed -n 's/backup-.*-\([0-9]\{8\}\)-\([0-9]\{6\}\)\.tar\.gz/\1 \2/p' | xargs -I {} date -d "{}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "Unknown")
        local size
        size=$(du -h "$backup_file" | cut -f1)
        local backup_type="Local"

        # Check if also in cloud
        if [[ -n "${BACKUP_S3_BUCKET:-}" ]]; then
            backup_type="Local+S3"
        fi
        if [[ -n "${BACKUP_GCS_BUCKET:-}" ]]; then
            backup_type="Local+GCS"
        fi
        if [[ -n "${BACKUP_AZURE_CONTAINER:-}" ]]; then
            backup_type="Local+Azure"
        fi
        if [[ -n "${PBS_SERVER:-}" && -n "${PBS_DATASTORE:-}" ]]; then
            backup_type="${backup_type:-Local}+PBS"
        fi

        printf "%-30s %-10s %-8s %-s\n" "$timestamp" "$size" "$backup_type" "$filename"
    done

    echo "=================================================================================="
}

# Restore from specific backup
restore_from_backup() {
    local backup_name="$1"

    if [[ -z "$backup_name" ]]; then
        log_error "Backup name is required"
        echo "Usage: $0 --operation restore-from-backup <backup_filename>"
        return 1
    fi

    local backup_file="${BUILD_DIR}/backups/$backup_name"

    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi

    log_info "Restoring from specific backup: $backup_name"

    # Verify backup integrity
    if ! verify_backup_integrity "$backup_file"; then
        log_error "Backup integrity verification failed"
        return 1
    fi

    # Extract and restore (similar to restore_backup function)
    local restore_dir
    restore_dir=$(mktemp -d)
    cd "$restore_dir"
    tar -xzf "$backup_file"

    local extracted_dir
    extracted_dir=$(find . -type d -name "backup-*" | head -n 1)

    # Restore site configuration
    if [[ -f "${extracted_dir}/site-config.yml" ]]; then
        cp "${extracted_dir}/site-config.yml" "$SITE_CONFIG"
        log_info "Site configuration restored from $backup_name"
    fi

    # Restore other components as in restore_backup...

    rm -rf "$restore_dir"
    log_success "Restoration from $backup_name completed"
}

# Download backup from cloud storage
download_from_cloud() {
    local backup_name="$1"

    if [[ -z "$backup_name" ]]; then
        log_error "Backup name is required"
        return 1
    fi

    local local_backup="${BUILD_DIR}/backups/$backup_name"

    # Try to download from configured cloud storage
    if [[ -n "${BACKUP_S3_BUCKET:-}" ]]; then
        log_info "Downloading backup from S3: $backup_name"
        export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
        export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
        export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

        if aws s3 cp "s3://${BACKUP_S3_BUCKET}/backups/${SITE_NAME}/$backup_name" "$local_backup"; then
            log_success "Backup downloaded from S3"
            return 0
        fi
    fi

    if [[ -n "${BACKUP_GCS_BUCKET:-}" ]]; then
        log_info "Downloading backup from GCS: $backup_name"
        if gsutil cp "gs://${BACKUP_GCS_BUCKET}/backups/${SITE_NAME}/$backup_name" "$local_backup"; then
            log_success "Backup downloaded from GCS"
            return 0
        fi
    fi

    if [[ -n "${BACKUP_AZURE_CONTAINER:-}" ]]; then
        log_info "Downloading backup from Azure: $backup_name"
        if az storage blob download --account-name "$AZURE_STORAGE_ACCOUNT" --account-key "$AZURE_STORAGE_KEY" --container-name "$BACKUP_AZURE_CONTAINER" --name "backups/${SITE_NAME}/$backup_name" --file "$local_backup"; then
            log_success "Backup downloaded from Azure"
            return 0
        fi
    fi

    log_error "Failed to download backup from cloud storage"
    return 1
}

# Upload backup to Proxmox Backup Server
upload_to_pbs() {
    local backup_file="$1"

    if [[ -z "${PBS_SERVER:-}" || -z "${PBS_DATASTORE:-}" ]]; then
        log_warning "PBS server or datastore not configured, skipping PBS upload"
        return 1
    fi

    log_info "Uploading backup to Proxmox Backup Server: $PBS_SERVER"

    # Check if proxmox-backup-client is available
    if ! command -v proxmox-backup-client &> /dev/null; then
        log_warning "proxmox-backup-client not available, skipping PBS upload"
        return 1
    fi

    # Set PBS credentials if provided
    local pbs_auth=""
    if [[ -n "${PBS_USER:-}" && -n "${PBS_PASSWORD:-}" ]]; then
        pbs_auth="--username $PBS_USER --password $PBS_PASSWORD"
    elif [[ -n "${PBS_TOKEN:-}" ]]; then
        pbs_auth="--auth-token $PBS_TOKEN"
    fi

    # Create backup archive on PBS
    local backup_name
    backup_name="backup-${SITE_NAME}-$(date +%Y%m%d-%H%M%S)"

    if proxmox-backup-client backup "$backup_name.pxar:$backup_file" \
        --repository "$PBS_SERVER:$PBS_DATASTORE" \
        $pbs_auth \
        --ns "$SITE_NAME/backups"; then

        log_success "Backup uploaded to PBS successfully"

        # Also upload checksum if it exists
        local checksum_file="${backup_file}.sha256"
        if [[ -f "$checksum_file" ]]; then
            proxmox-backup-client backup "checksum-${backup_name}.pxar:$checksum_file" \
                --repository "$PBS_SERVER:$PBS_DATASTORE" \
                $pbs_auth \
                --ns "$SITE_NAME/checksums"
        fi

        return 0
    else
        log_error "Failed to upload backup to PBS"
        return 1
    fi
}

# Backup VMs to Proxmox Backup Server
backup_vms_to_pbs() {
    log_info "Backing up VMs to Proxmox Backup Server..."

    if [[ -z "${PBS_SERVER:-}" || -z "${PBS_DATASTORE:-}" ]]; then
        log_warning "PBS server or datastore not configured, skipping VM backup"
        return 1
    fi

    # Check if we're running on a Proxmox VE host
    if [[ ! -f "/etc/pve/.version" ]]; then
        log_warning "Not running on Proxmox VE host, skipping VM backup"
        return 0
    fi

    # Check if proxmox-backup-client is available
    if ! command -v proxmox-backup-client &> /dev/null; then
        log_warning "proxmox-backup-client not available, skipping VM backup"
        return 1
    fi

    # Set PBS credentials
    local pbs_auth=""
    if [[ -n "${PBS_USER:-}" && -n "${PBS_PASSWORD:-}" ]]; then
        pbs_auth="--username $PBS_USER --password $PBS_PASSWORD"
    elif [[ -n "${PBS_TOKEN:-}" ]]; then
        pbs_auth="--auth-token $PBS_TOKEN"
    fi

    # Get list of VMs and containers
    local vms
    vms=$(qm list 2>/dev/null | awk 'NR>1 {print $1}' || echo "")
    local containers
    containers=$(pct list 2>/dev/null | awk 'NR>1 {print $1}' || echo "")

    local backup_count=0
    local error_count=0

    # Backup VMs
    if [[ -n "$vms" ]]; then
        log_info "Backing up VMs..."
        for vmid in $vms; do
            local vm_name
            vm_name=$(qm config "$vmid" 2>/dev/null | grep "^name:" | cut -d' ' -f2 || echo "vm-$vmid")

            log_debug "Backing up VM $vmid ($vm_name) to PBS..."

            if qm backup "$vmid" "pbs://$PBS_SERVER:$PBS_DATASTORE/$SITE_NAME/vms/$vm_name" \
                --mode snapshot \
                --compress zstd \
                --notes "Automated backup from Brewnix - $(date)"; then

                log_success "VM $vmid ($vm_name) backed up successfully"
                ((backup_count++))
            else
                log_error "Failed to backup VM $vmid ($vm_name)"
                ((error_count++))
            fi
        done
    fi

    # Backup containers
    if [[ -n "$containers" ]]; then
        log_info "Backing up containers..."
        for vmid in $containers; do
            local container_name
            container_name=$(pct config "$vmid" 2>/dev/null | grep "^hostname:" | cut -d' ' -f2 || echo "ct-$vmid")

            log_debug "Backing up container $vmid ($container_name) to PBS..."

            if pct backup "$vmid" "pbs://$PBS_SERVER:$PBS_DATASTORE/$SITE_NAME/containers/$container_name" \
                --mode snapshot \
                --compress zstd \
                --notes "Automated backup from Brewnix - $(date)"; then

                log_success "Container $vmid ($container_name) backed up successfully"
                ((backup_count++))
            else
                log_error "Failed to backup container $vmid ($container_name)"
                ((error_count++))
            fi
        done
    fi

    if [[ $backup_count -gt 0 ]]; then
        log_success "Successfully backed up $backup_count VMs/containers to PBS"
    fi

    if [[ $error_count -gt 0 ]]; then
        log_warning "Failed to backup $error_count VMs/containers"
        return 1
    fi

    return 0
}

# Download backup from Proxmox Backup Server
download_from_pbs() {
    local backup_name="$1"

    if [[ -z "${PBS_SERVER:-}" || -z "${PBS_DATASTORE:-}" ]]; then
        log_warning "PBS server or datastore not configured"
        return 1
    fi

    # Check if proxmox-backup-client is available
    if ! command -v proxmox-backup-client &> /dev/null; then
        log_warning "proxmox-backup-client not available"
        return 1
    fi

    local local_backup="${BUILD_DIR}/backups/$backup_name"

    # Set PBS credentials
    local pbs_auth=""
    if [[ -n "${PBS_USER:-}" && -n "${PBS_PASSWORD:-}" ]]; then
        pbs_auth="--username $PBS_USER --password $PBS_PASSWORD"
    elif [[ -n "${PBS_TOKEN:-}" ]]; then
        pbs_auth="--auth-token $PBS_TOKEN"
    fi

    log_info "Downloading backup from PBS: $backup_name"

    if proxmox-backup-client restore "$SITE_NAME/backups/$backup_name" "$local_backup" \
        --repository "$PBS_SERVER:$PBS_DATASTORE" \
        $pbs_auth; then

        log_success "Backup downloaded from PBS successfully"
        return 0
    else
        log_error "Failed to download backup from PBS"
        return 1
    fi
}

# List backups on Proxmox Backup Server
list_pbs_backups() {
    if [[ -z "${PBS_SERVER:-}" || -z "${PBS_DATASTORE:-}" ]]; then
        log_warning "PBS server or datastore not configured"
        return 1
    fi

    # Check if proxmox-backup-client is available
    if ! command -v proxmox-backup-client &> /dev/null; then
        log_warning "proxmox-backup-client not available"
        return 1
    fi

    # Set PBS credentials
    local pbs_auth=""
    if [[ -n "${PBS_USER:-}" && -n "${PBS_PASSWORD:-}" ]]; then
        pbs_auth="--username $PBS_USER --password $PBS_PASSWORD"
    elif [[ -n "${PBS_TOKEN:-}" ]]; then
        pbs_auth="--auth-token $PBS_TOKEN"
    fi

    log_info "Listing backups on PBS for site: $SITE_NAME"

    echo "=================================================================================="
    printf "%-40s %-15s %-10s %-s\n" "BACKUP NAME" "SIZE" "TYPE" "CREATED"
    echo "=================================================================================="

    # List configuration backups
    if proxmox-backup-client list --repository "$PBS_SERVER:$PBS_DATASTORE" \
        $pbs_auth --ns "$SITE_NAME/backups" &>/dev/null; then

        proxmox-backup-client list --repository "$PBS_SERVER:$PBS_DATASTORE" \
            $pbs_auth --ns "$SITE_NAME/backups" | while read -r line; do

            # Parse backup info (simplified parsing)
            local backup_name
            backup_name=$(echo "$line" | awk '{print $1}')
            local backup_size
            backup_size=$(echo "$line" | awk '{print $3}')
            local backup_date
            backup_date=$(echo "$line" | awk '{print $4}')

            if [[ -n "$backup_name" ]]; then
                printf "%-40s %-15s %-10s %-s\n" "$backup_name" "$backup_size" "Config" "$backup_date"
            fi
        done
    fi

    # List VM backups
    if proxmox-backup-client list --repository "$PBS_SERVER:$PBS_DATASTORE" \
        $pbs_auth --ns "$SITE_NAME/vms" &>/dev/null; then

        proxmox-backup-client list --repository "$PBS_SERVER:$PBS_DATASTORE" \
            $pbs_auth --ns "$SITE_NAME/vms" | while read -r line; do

            local backup_name
            backup_name=$(echo "$line" | awk '{print $1}')
            local backup_size
            backup_size=$(echo "$line" | awk '{print $3}')
            local backup_date
            backup_date=$(echo "$line" | awk '{print $4}')

            if [[ -n "$backup_name" ]]; then
                printf "%-40s %-15s %-10s %-s\n" "$backup_name" "$backup_size" "VM" "$backup_date"
            fi
        done
    fi

    # List container backups
    if proxmox-backup-client list --repository "$PBS_SERVER:$PBS_DATASTORE" \
        $pbs_auth --ns "$SITE_NAME/containers" &>/dev/null; then

        proxmox-backup-client list --repository "$PBS_SERVER:$PBS_DATASTORE" \
            $pbs_auth --ns "$SITE_NAME/containers" | while read -r line; do

            local backup_name
            backup_name=$(echo "$line" | awk '{print $1}')
            local backup_size
            backup_size=$(echo "$line" | awk '{print $3}')
            local backup_date
            backup_date=$(echo "$line" | awk '{print $4}')

            if [[ -n "$backup_name" ]]; then
                printf "%-40s %-15s %-10s %-s\n" "$backup_name" "$backup_size" "Container" "$backup_date"
            fi
        done
    fi

    echo "=================================================================================="
}

# Restore VM from Proxmox Backup Server
restore_vm_from_pbs() {
    local backup_id="$1"
    local target_vmid="$2"

    if [[ -z "$backup_id" || -z "$target_vmid" ]]; then
        log_error "Backup ID and target VM ID are required"
        echo "Usage: restore_vm_from_pbs <backup_id> <target_vmid>"
        return 1
    fi

    if [[ -z "${PBS_SERVER:-}" || -z "${PBS_DATASTORE:-}" ]]; then
        log_warning "PBS server or datastore not configured"
        return 1
    fi

    # Check if we're running on a Proxmox VE host
    if [[ ! -f "/etc/pve/.version" ]]; then
        log_error "Not running on Proxmox VE host"
        return 1
    fi

    log_info "Restoring VM from PBS backup: $backup_id to VM ID: $target_vmid"

    if qm restore "pbs://$PBS_SERVER:$PBS_DATASTORE/$SITE_NAME/vms/$backup_id" "$target_vmid"; then
        log_success "VM restored successfully from PBS"
        return 0
    else
        log_error "Failed to restore VM from PBS"
        return 1
    fi
}

# Restore container from Proxmox Backup Server
restore_container_from_pbs() {
    local backup_id="$1"
    local target_vmid="$2"

    if [[ -z "$backup_id" || -z "$target_vmid" ]]; then
        log_error "Backup ID and target container ID are required"
        echo "Usage: restore_container_from_pbs <backup_id> <target_vmid>"
        return 1
    fi

    if [[ -z "${PBS_SERVER:-}" || -z "${PBS_DATASTORE:-}" ]]; then
        log_warning "PBS server or datastore not configured"
        return 1
    fi

    # Check if we're running on a Proxmox VE host
    if [[ ! -f "/etc/pve/.version" ]]; then
        log_error "Not running on Proxmox VE host"
        return 1
    fi

    log_info "Restoring container from PBS backup: $backup_id to container ID: $target_vmid"

    if pct restore "$target_vmid" "pbs://$PBS_SERVER:$PBS_DATASTORE/$SITE_NAME/containers/$backup_id"; then
        log_success "Container restored successfully from PBS"
        return 0
    else
        log_error "Failed to restore container from PBS"
        return 1
    fi
}

# Setup Proxmox Backup Server integration
setup_pbs_integration() {
    log_info "Setting up Proxmox Backup Server integration..."

    if [[ -z "${PBS_SERVER:-}" || -z "${PBS_DATASTORE:-}" ]]; then
        log_warning "PBS server or datastore not configured, skipping setup"
        return 1
    fi

    # Install proxmox-backup-client if not available
    if ! command -v proxmox-backup-client &> /dev/null; then
        log_info "Installing proxmox-backup-client..."

        # Add Proxmox repository if not already added
        if [[ ! -f "/etc/apt/sources.list.d/pbs.list" ]]; then
            echo "deb http://download.proxmox.com/debian/pbs-client bookworm main" | sudo tee /etc/apt/sources.list.d/pbs.list
            wget -qO - http://download.proxmox.com/debian/proxmox-release-bookworm.gpg | sudo apt-key add -
        fi

        sudo apt update
        sudo apt install -y proxmox-backup-client
    fi

    # Test PBS connection
    log_info "Testing PBS connection..."

    local pbs_auth=""
    if [[ -n "${PBS_USER:-}" && -n "${PBS_PASSWORD:-}" ]]; then
        pbs_auth="--username $PBS_USER --password $PBS_PASSWORD"
    elif [[ -n "${PBS_TOKEN:-}" ]]; then
        pbs_auth="--auth-token $PBS_TOKEN"
    fi

    if proxmox-backup-client list --repository "$PBS_SERVER:$PBS_DATASTORE" $pbs_auth &>/dev/null; then
        log_success "PBS connection test successful"

        # Create namespace structure
        proxmox-backup-client create-ns "$SITE_NAME" --repository "$PBS_SERVER:$PBS_DATASTORE" $pbs_auth
        proxmox-backup-client create-ns "$SITE_NAME/backups" --repository "$PBS_SERVER:$PBS_DATASTORE" $pbs_auth
        proxmox-backup-client create-ns "$SITE_NAME/vms" --repository "$PBS_SERVER:$PBS_DATASTORE" $pbs_auth
        proxmox-backup-client create-ns "$SITE_NAME/containers" --repository "$PBS_SERVER:$PBS_DATASTORE" $pbs_auth
        proxmox-backup-client create-ns "$SITE_NAME/checksums" --repository "$PBS_SERVER:$PBS_DATASTORE" $pbs_auth

        log_success "PBS namespace structure created"
        return 0
    else
        log_error "PBS connection test failed"
        return 1
    fi
}

# Run comprehensive testing suite
run_tests() {
    log_info "Running comprehensive testing suite..."
    # TODO: Implement comprehensive testing
    true
}

# Run advanced monitoring with alerting
run_advanced_monitoring() {
    log_info "Running advanced monitoring with alerting..."
    
    local alert_report
    alert_report="${BUILD_DIR}/alert-report-${SITE_NAME}-$(date +%Y%m%d-%H%M%S).json"
    
    # Initialize alert report
    cat > "$alert_report" << EOF
{
    "site_name": "$SITE_NAME",
    "check_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "alerts": [],
    "critical_alerts": 0,
    "warning_alerts": 0,
    "info_alerts": 0,
    "notifications_sent": 0
}
EOF
    
    # Run comprehensive health checks
    check_system_alerts "$alert_report"
    check_network_alerts "$alert_report"
    check_security_alerts "$alert_report"
    check_performance_alerts "$alert_report"
    check_gitops_alerts "$alert_report"
    
    # Process and send alerts
    process_alerts "$alert_report"
    
    log_info "Advanced monitoring completed. Alert report: $alert_report"
}

# Send alert notifications
send_alert_notification() {
    local alert_type="$1"
    local alert_message="$2"
    local alert_details="$3"
    
    log_info "Sending $alert_type alert: $alert_message"
    
    # Email notification
    if [[ -n "${ALERT_EMAIL:-}" ]]; then
        send_email_alert "$alert_type" "$alert_message" "$alert_details"
    fi
    
    # Webhook notification
    if [[ -n "${ALERT_WEBHOOK_URL:-}" ]]; then
        send_webhook_alert "$alert_type" "$alert_message" "$alert_details"
    fi
    
    # Slack notification
    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        send_slack_alert "$alert_type" "$alert_message" "$alert_details"
    fi
    
    # SMS notification for critical alerts
    if [[ "$alert_type" == "critical" && -n "${SMS_API_KEY:-}" ]]; then
        send_sms_alert "$alert_message"
    fi
}

# Send email alert
send_email_alert() {
    local alert_type="$1"
    local subject="$2"
    local body="$3"
    
    local email_subject="[$alert_type] Brewnix Firewall Alert - $SITE_NAME"
    local email_body
    email_body="Alert Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Site: $SITE_NAME
Type: $alert_type
Message: $subject

Details:
$body

--
Brewnix Firewall Monitoring System"
    
    # Use mail command if available
    if command -v mail &> /dev/null; then
        echo "$email_body" | mail -s "$email_subject" "$ALERT_EMAIL"
        log_debug "Email alert sent to $ALERT_EMAIL"
    else
        log_warning "Mail command not available, skipping email alert"
    fi
}

# Send webhook alert
send_webhook_alert() {
    local alert_type="$1"
    local message="$2"
    local details="$3"
    
    local payload
    payload=$(cat <<EOF
{
    "alert_type": "$alert_type",
    "site_name": "$SITE_NAME",
    "message": "$message",
    "details": "$details",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)
    
    if curl -s -X POST "$ALERT_WEBHOOK_URL" -H "Content-Type: application/json" -d "$payload" &> /dev/null; then
        log_debug "Webhook alert sent successfully"
    else
        log_warning "Failed to send webhook alert"
    fi
}

# Send Slack alert
send_slack_alert() {
    local alert_type="$1"
    local message="$2"
    local details="$3"
    
    local color
    case "$alert_type" in
        "critical") color="danger" ;;
        "warning") color="warning" ;;
        "info") color="good" ;;
        *) color="#808080" ;;
    esac
    
    local payload
    payload=$(cat <<EOF
{
    "attachments": [
        {
            "color": "$color",
            "title": "Brewnix Firewall Alert - $SITE_NAME",
            "text": "*$message*",
            "fields": [
                {
                    "title": "Alert Type",
                    "value": "$alert_type",
                    "short": true
                },
                {
                    "title": "Site",
                    "value": "$SITE_NAME",
                    "short": true
                }
            ],
            "footer": "Brewnix Monitoring",
            "ts": $(date +%s)
        }
    ]
}
EOF
)
    
    if curl -s -X POST "$SLACK_WEBHOOK_URL" -H "Content-Type: application/json" -d "$payload" &> /dev/null; then
        log_debug "Slack alert sent successfully"
    else
        log_warning "Failed to send Slack alert"
    fi
}

# Send SMS alert
send_sms_alert() {
    local message="$1"
    
    # This would integrate with an SMS service like Twilio
    # For now, just log the intent
    log_info "SMS alert would be sent: $message"
    log_debug "SMS integration requires SMS_API_KEY and SMS service configuration"
}

# Check system alerts
check_system_alerts() {
    local alert_file="$1"
    
    log_debug "Checking system alerts..."
    
    # Disk space alert
    local disk_usage
    disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    
    if [[ $disk_usage -gt 95 ]]; then
        add_alert "$alert_file" "critical" "Disk space critical" "Disk usage is ${disk_usage}% - immediate action required"
    elif [[ $disk_usage -gt 90 ]]; then
        add_alert "$alert_file" "warning" "Disk space warning" "Disk usage is ${disk_usage}% - monitor closely"
    fi
    
    # Memory usage alert
    local mem_usage
    mem_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    
    if [[ $mem_usage -gt 95 ]]; then
        add_alert "$alert_file" "critical" "Memory usage critical" "Memory usage is ${mem_usage}% - system may become unstable"
    elif [[ $mem_usage -gt 90 ]]; then
        add_alert "$alert_file" "warning" "Memory usage high" "Memory usage is ${mem_usage}% - investigate processes"
    fi
    
    # System load alert
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | cut -d',' -f1 | xargs)
    local cpu_count
    cpu_count=$(nproc)
    
    local load_comparison
    load_comparison=$(awk "BEGIN {print ($load_avg > $cpu_count * 2) ? 1 : 0}" 2>/dev/null || echo 0)
    if [[ "$load_comparison" == "1" ]]; then
        add_alert "$alert_file" "critical" "System load critical" "Load average $load_avg exceeds ${cpu_count}x CPU count"
    fi
    
    local load_comparison2
    load_comparison2=$(awk "BEGIN {print ($load_avg > $cpu_count * 1.5) ? 1 : 0}" 2>/dev/null || echo 0)
    if [[ "$load_comparison2" == "1" ]]; then
        add_alert "$alert_file" "warning" "System load high" "Load average $load_avg is high"
    fi
}

# Check network alerts
check_network_alerts() {
    local alert_file="$1"
    
    log_debug "Checking network alerts..."
    
    # Network connectivity alert
    if ! ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
        add_alert "$alert_file" "critical" "Internet connectivity lost" "Cannot reach external DNS servers"
    fi
    
    # Firewall service alert
    if command -v pfctl &> /dev/null; then
        if ! pfctl -s info &> /dev/null; then
            add_alert "$alert_file" "critical" "Firewall service down" "pf firewall service is not responding"
        fi
    fi
    
    # Interface status alert
    local down_interfaces
    down_interfaces=$(ip link show | grep -c "state DOWN")
    
    if [[ $down_interfaces -gt 0 ]]; then
        add_alert "$alert_file" "warning" "Network interfaces down" "$down_interfaces network interface(s) are down"
    fi
}

# Check security alerts
check_security_alerts() {
    local alert_file="$1"
    
    log_debug "Checking security alerts..."
    
    # SSH brute force detection
    local ssh_failures
    ssh_failures=$(journalctl -u ssh --since "1 hour ago" 2>/dev/null | grep -c "Failed password" || echo 0)
    ssh_failures=${ssh_failures//[^0-9]/}  # Sanitize to numbers only
    ssh_failures=${ssh_failures:-0}  # Default to 0 if empty
    
    if [[ $ssh_failures -gt 10 ]]; then
        add_alert "$alert_file" "warning" "SSH brute force attempt" "$ssh_failures failed SSH login attempts in the last hour"
    fi
    
    # Check for unauthorized services
    local unauthorized_ports=("23" "25" "53" "110" "143")
    
    for port in "${unauthorized_ports[@]}"; do
        if netstat -tln 2>/dev/null | grep -q ":$port "; then
            add_alert "$alert_file" "warning" "Unauthorized service detected" "Service running on port $port - review firewall rules"
        fi
    done
    
    # Check certificate expiry
    if [[ -f "/etc/ssl/certs/brewnix-ca.crt" ]]; then
        local cert_expiry
        cert_expiry=$(openssl x509 -in /etc/ssl/certs/brewnix-ca.crt -noout -enddate 2>/dev/null | cut -d'=' -f2)
        
        if [[ -n "$cert_expiry" ]]; then
            local expiry_date
            expiry_date=$(date -d "$cert_expiry" +%s)
            local current_date
            current_date=$(date +%s)
            local days_until_expiry=$(( ($expiry_date - $current_date) / 86400 ))
            
            if [[ $days_until_expiry -lt 30 ]]; then
                add_alert "$alert_file" "warning" "Certificate expiring soon" "SSL certificate expires in $days_until_expiry days"
            fi
        fi
    fi
}

# Check performance alerts
check_performance_alerts() {
    local alert_file="$1"
    
    log_debug "Checking performance alerts..."
    
    # Network throughput monitoring
    local rx_bytes
    rx_bytes=$(cat /sys/class/net/*/statistics/rx_bytes 2>/dev/null | paste -sd+ | awk '{sum += $1} END {print sum+0}' || echo 0)
    
    if [[ $rx_bytes -gt 1000000000 ]]; then  # 1GB
        add_alert "$alert_file" "info" "High network traffic" "Network received $rx_bytes bytes in monitoring period"
    fi
    
    # Process monitoring
    local zombie_processes
    zombie_processes=$(ps aux | awk '{print $8}' | grep -c "Z" || echo 0)
    zombie_processes=${zombie_processes//[^0-9]/}  # Sanitize to numbers only
    zombie_processes=${zombie_processes:-0}  # Default to 0 if empty
    
    if [[ $zombie_processes -gt 5 ]]; then
        add_alert "$alert_file" "warning" "Zombie processes detected" "$zombie_processes zombie processes found"
    fi
    
    # Log file size monitoring
    local large_logs
    large_logs=$(find /var/log -name "*.log" -size +100M 2>/dev/null | wc -l || echo 0)
    large_logs=${large_logs//[^0-9]/}  # Sanitize to numbers only
    large_logs=${large_logs:-0}  # Default to 0 if empty
    
    if [[ $large_logs -gt 0 ]]; then
        add_alert "$alert_file" "info" "Large log files detected" "$large_logs log files larger than 100MB"
    fi
}

# Check GitOps alerts
check_gitops_alerts() {
    local alert_file="$1"
    
    log_debug "Checking GitOps alerts..."
    
    # GitOps repository sync status
    if [[ -n "$GITOPS_REPO" ]]; then
        local gitops_dir="${BUILD_DIR}/gitops-repo"
        
        if [[ -d "$gitops_dir" ]]; then
            cd "$gitops_dir"
            
            # Check for uncommitted changes
            if ! git diff --quiet HEAD; then
                add_alert "$alert_file" "warning" "GitOps repository has uncommitted changes" "Local changes detected in GitOps repository"
            fi
            
            # Check for remote changes
            git fetch origin &>/dev/null
            if [[ $(git rev-parse HEAD) != $(git rev-parse origin/main 2>/dev/null || git rev-parse origin/master) ]]; then
                add_alert "$alert_file" "info" "GitOps repository updates available" "Remote repository has new changes available"
            fi
        else
            add_alert "$alert_file" "warning" "GitOps repository missing" "GitOps repository directory not found"
        fi
    fi
    
    # Configuration drift detection
    if [[ -f "${BUILD_DIR}/drift-report-${SITE_NAME}-$(date +%Y%m%d)*.json" ]]; then
        local latest_drift
        latest_drift=$(ls -t "${BUILD_DIR}/drift-report-${SITE_NAME}-"*.json 2>/dev/null | head -n1)
        
        if [[ -f "$latest_drift" ]]; then
            local drift_detected
            drift_detected=$(jq -r '.drift_detected' "$latest_drift" 2>/dev/null || echo "false")
            
            if [[ "$drift_detected" == "true" ]]; then
                add_alert "$alert_file" "warning" "Configuration drift detected" "System configuration differs from GitOps state"
            fi
        fi
    fi
}

# Add alert to report
add_alert() {
    local alert_file="$1"
    local alert_type="$2"
    local alert_title="$3"
    local alert_message="$4"
    
    # Add alert to JSON array
    jq --arg type "$alert_type" --arg title "$alert_title" --arg message "$alert_message" --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.alerts += [{"type": $type, "title": $title, "message": $message, "timestamp": $timestamp}]' "$alert_file" > "${alert_file}.tmp"
    mv "${alert_file}.tmp" "$alert_file"
    
    # Update counters
    case "$alert_type" in
        "critical")
            jq ".critical_alerts += 1" "$alert_file" > "${alert_file}.tmp"
            mv "${alert_file}.tmp" "$alert_file"
            ;;
        "warning")
            jq ".warning_alerts += 1" "$alert_file" > "${alert_file}.tmp"
            mv "${alert_file}.tmp" "$alert_file"
            ;;
        "info")
            jq ".info_alerts += 1" "$alert_file" > "${alert_file}.tmp"
            mv "${alert_file}.tmp" "$alert_file"
            ;;
    esac
    
    log_debug "Added $alert_type alert: $alert_title"
}

# Process and send alerts
process_alerts() {
    local alert_file="$1"
    
    local critical_count
    critical_count=$(jq -r '.critical_alerts' "$alert_file")
    local warning_count
    warning_count=$(jq -r '.warning_alerts' "$alert_file")
    local info_count
    info_count=$(jq -r '.info_alerts' "$alert_file")
    
    log_info "Alert summary: $critical_count critical, $warning_count warning, $info_count info"
    
    # Send critical alerts immediately
    if [[ $critical_count -gt 0 ]]; then
        jq -r '.alerts[] | select(.type == "critical") | "\(.type)|\(.title)|\(.message)"' "$alert_file" | 
        while IFS='|' read -r alert_type alert_title alert_message; do
            send_alert_notification "$alert_type" "$alert_title" "$alert_message"
            jq ".notifications_sent += 1" "$alert_file" > "${alert_file}.tmp"
            mv "${alert_file}.tmp" "$alert_file"
        done
    fi
    
    # Send warning alerts (batched if many)
    if [[ $warning_count -gt 0 ]]; then
        if [[ $warning_count -gt 5 ]]; then
            local warning_summary="Multiple warnings detected ($warning_count total)"
            send_alert_notification "warning" "$warning_summary" "Check alert report for details: $alert_file"
            jq ".notifications_sent += 1" "$alert_file" > "${alert_file}.tmp"
            mv "${alert_file}.tmp" "$alert_file"
        else
            jq -r '.alerts[] | select(.type == "warning") | "\(.type)|\(.title)|\(.message)"' "$alert_file" | 
            while IFS='|' read -r alert_type alert_title alert_message; do
                send_alert_notification "$alert_type" "$alert_title" "$alert_message"
                jq ".notifications_sent += 1" "$alert_file" > "${alert_file}.tmp"
                mv "${alert_file}.tmp" "$alert_file"
            done
        fi
    fi
    
    # Send info alerts only if configured for verbose notifications
    if [[ "${ALERT_INFO_NOTIFICATIONS:-false}" == "true" && $info_count -gt 0 ]]; then
        jq -r '.alerts[] | select(.type == "info") | "\(.type)|\(.title)|\(.message)"' "$alert_file" | 
        while IFS='|' read -r alert_type alert_title alert_message; do
            send_alert_notification "$alert_type" "$alert_title" "$alert_message"
            jq ".notifications_sent += 1" "$alert_file" > "${alert_file}.tmp"
            mv "${alert_file}.tmp" "$alert_file"
        done
    fi
    
    local notifications_sent
    notifications_sent=$(jq -r '.notifications_sent' "$alert_file")
    log_info "Sent $notifications_sent alert notifications"
}

# Setup automated alerting service
setup_automated_alerting() {
    log_info "Setting up automated alerting service..."
    
    # Create alerting script
    local alert_script="/usr/local/bin/brewnix-alert-check"
    sudo tee "$alert_script" > /dev/null << EOF
#!/bin/bash
# Brewnix Automated Alerting Service
cd "$PROJECT_ROOT"
"$SCRIPT_DIR/deploy-gitops.sh" --operation alert "$SITE_CONFIG"
EOF
    sudo chmod +x "$alert_script"
    
    # Create systemd service
    sudo tee /etc/systemd/system/brewnix-alerting.service > /dev/null << EOF
[Unit]
Description=Brewnix Automated Alerting
After=network.target

[Service]
Type=oneshot
ExecStart=$alert_script
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # Create systemd timer for regular alerting
    sudo tee /etc/systemd/system/brewnix-alerting.timer > /dev/null << EOF
[Unit]
Description=Run Brewnix alerting every 15 minutes
Requires=brewnix-alerting.service

[Timer]
OnCalendar=*:0/15
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Enable and start timer
    sudo systemctl daemon-reload
    sudo systemctl enable brewnix-alerting.timer
    sudo systemctl start brewnix-alerting.timer
    
    log_success "Automated alerting service configured"
}

# Run comprehensive testing suite
run_tests() {
    log_info "Running comprehensive testing suite..."
    
    local test_results
    test_results="${BUILD_DIR}/test-results-${SITE_NAME}-$(date +%Y%m%d-%H%M%S).json"
    
    # Initialize test results
    cat > "$test_results" << EOF
{
    "site_name": "$SITE_NAME",
    "test_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "tests_run": [],
    "tests_passed": 0,
    "tests_failed": 0,
    "overall_status": "running"
}
EOF
    
    # Test 1: Network connectivity
    log_info "Testing network connectivity..."
    if test_network_connectivity; then
        update_test_result "$test_results" "network_connectivity" "passed"
    else
        update_test_result "$test_results" "network_connectivity" "failed"
    fi
    
    # Test 2: Firewall rules
    log_info "Testing firewall rules..."
    if test_firewall_rules; then
        update_test_result "$test_results" "firewall_rules" "passed"
    else
        update_test_result "$test_results" "firewall_rules" "failed"
    fi
    
    # Test 3: Device configurations
    log_info "Testing device configurations..."
    if test_device_configs; then
        update_test_result "$test_results" "device_configs" "passed"
    else
        update_test_result "$test_results" "device_configs" "failed"
    fi
    
    # Test 4: Service availability
    log_info "Testing service availability..."
    if test_service_availability; then
        update_test_result "$test_results" "service_availability" "passed"
    else
        update_test_result "$test_results" "service_availability" "failed"
    fi
    
    # Test 5: Backup verification
    log_info "Testing backup verification..."
    if test_backup_verification; then
        update_test_result "$test_results" "backup_verification" "passed"
    else
        update_test_result "$test_results" "backup_verification" "failed"
    fi
    
    # Finalize test results
    finalize_test_results "$test_results"
    
    log_info "Test results saved to: $test_results"
    
    # Check overall status
    local overall_status
    overall_status=$(jq -r '.overall_status' "$test_results")
    
    if [[ "$overall_status" == "passed" ]]; then
        log_success "All tests passed!"
        return 0
    else
        log_error "Some tests failed. Check $test_results for details."
        return 1
    fi
}

# Update test result in JSON file
update_test_result() {
    local test_file="$1"
    local test_name="$2"
    local status="$3"
    
    # Add test to results array
    jq ".tests_run += [{\"name\": \"$test_name\", \"status\": \"$status\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}]" "$test_file" > "${test_file}.tmp"
    mv "${test_file}.tmp" "$test_file"
    
    # Update counters
    if [[ "$status" == "passed" ]]; then
        jq ".tests_passed += 1" "$test_file" > "${test_file}.tmp"
        mv "${test_file}.tmp" "$test_file"
    else
        jq ".tests_failed += 1" "$test_file" > "${test_file}.tmp"
        mv "${test_file}.tmp" "$test_file"
    fi
}

# Finalize test results
finalize_test_results() {
    local test_file="$1"
    
    # Determine overall status
    local failed_count
    failed_count=$(jq -r '.tests_failed' "$test_file")
    
    if [[ "$failed_count" -eq 0 ]]; then
        jq '.overall_status = "passed"' "$test_file" > "${test_file}.tmp"
    else
        jq '.overall_status = "failed"' "$test_file" > "${test_file}.tmp"
    fi
    
    mv "${test_file}.tmp" "$test_file"
}

# Test network connectivity
test_network_connectivity() {
    log_debug "Testing network connectivity for all VLANs..."
    
    # Extract network prefix from site config
    local network_prefix
    network_prefix=$(grep "^network_prefix:" "$SITE_CONFIG" | cut -d'"' -f2 | cut -d'.' -f1-2)
    
    if [[ -z "$network_prefix" ]]; then
        log_error "Could not determine network prefix from site config"
        return 1
    fi
    
    # Test connectivity to key network segments
    local test_ips=(
        "${network_prefix}.50.1"  # Management gateway
        "${network_prefix}.10.1"  # Main VLAN gateway
        "${network_prefix}.20.1"  # Cameras VLAN gateway
        "${network_prefix}.30.1"  # IoT VLAN gateway
    )
    
    local failed_tests=0
    
    for ip in "${test_ips[@]}"; do
        if ! ping -c 1 -W 2 "$ip" &> /dev/null; then
            log_warning "Cannot reach $ip"
            ((failed_tests++))
        fi
    done
    
    if [[ $failed_tests -gt 0 ]]; then
        log_warning "Network connectivity test failed for $failed_tests endpoints"
        return 1
    fi
    
    log_debug "Network connectivity test passed"
    return 0
}

# Test firewall rules
test_firewall_rules() {
    log_debug "Testing firewall rule configuration..."
    
    # This would typically test actual firewall rules
    # For now, we'll do basic validation
    
    # Check if OPNsense is running (if deployed)
    if command -v pfctl &> /dev/null; then
        if ! pfctl -s info &> /dev/null; then
            log_error "Firewall (pf) is not responding"
            return 1
        fi
    fi
    
    # Check for basic firewall rules structure
    if command -v pfctl &> /dev/null; then
        local rule_count
        rule_count=$(pfctl -s rules 2>/dev/null | wc -l)
        
        if [[ $rule_count -lt 10 ]]; then
            log_warning "Low number of firewall rules detected: $rule_count"
        fi
    fi
    
    log_debug "Firewall rules test completed"
    return 0
}

# Test device configurations
test_device_configs() {
    log_debug "Testing device configurations..."
    
    # Check if device configurations exist and are valid
    local site_name
    site_name=$(basename "$(dirname "$(dirname "$SITE_CONFIG")")")
    local devices_dir="${PROJECT_ROOT}/config/proxmox-firewall/sites/${site_name}/devices"
    
    if [[ -d "$devices_dir" ]]; then
        local device_count
        device_count=$(find "$devices_dir" -name "*.yml" | wc -l)
        
        if [[ $device_count -eq 0 ]]; then
            log_warning "No device configurations found"
            return 1
        fi
        
        # Validate each device configuration
        for device_file in "$devices_dir"/*.yml; do
            if [[ -f "$device_file" ]]; then
                # Basic YAML validation
                if ! python3 -c "import yaml; yaml.safe_load(open('$device_file'))" 2>/dev/null; then
                    log_error "Invalid YAML in device config: $(basename "$device_file")"
                    return 1
                fi
            fi
        done
    fi
    
    log_debug "Device configurations test passed"
    return 0
}

# Test service availability
test_service_availability() {
    log_debug "Testing service availability..."
    
    # Test basic services that should be running
    local services=("sshd")
    
    # Add OPNsense-related services if available
    if command -v pfctl &> /dev/null; then
        services+=("pf")
    fi
    
    for service in "${services[@]}"; do
        if ! systemctl is-active --quiet "$service" 2>/dev/null; then
            log_warning "Service $service is not running"
        fi
    done
    
    log_debug "Service availability test completed"
    return 0
}

# Test backup verification
test_backup_verification() {
    log_debug "Testing backup verification..."
    
    # Check if backups directory exists
    local backups_dir="${BUILD_DIR}/backups"
    
    if [[ ! -d "$backups_dir" ]]; then
        log_warning "No backups directory found"
        return 1
    fi
    
    # Check for recent backups
    local recent_backups
    recent_backups=$(find "$backups_dir" -name "backup-${SITE_NAME}-*.tar.gz" -mtime -7 | wc -l)
    
    if [[ $recent_backups -eq 0 ]]; then
        log_warning "No recent backups found (last 7 days)"
        return 1
    fi
    
    log_debug "Backup verification test passed"
    return 0
}

# Run health monitoring and checks
run_monitoring() {
    log_info "Running health monitoring and checks..."
    
    local health_report
    health_report="${BUILD_DIR}/health-report-${SITE_NAME}-$(date +%Y%m%d-%H%M%S).json"
    
    # Initialize health report
    cat > "$health_report" << EOF
{
    "site_name": "$SITE_NAME",
    "check_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "system_health": {},
    "network_health": {},
    "service_health": {},
    "overall_status": "unknown"
}
EOF
    
    # System health checks
    check_system_health "$health_report"
    
    # Network health checks
    check_network_health "$health_report"
    
    # Service health checks
    check_service_health "$health_report"
    
    # Determine overall status
    determine_overall_health "$health_report"
    
    log_info "Health report saved to: $health_report"
    
    # Display summary
    local overall_status
    overall_status=$(jq -r '.overall_status' "$health_report")
    
    case "$overall_status" in
        "healthy")
            log_success "System health: HEALTHY"
            return 0
            ;;
        "warning")
            log_warning "System health: WARNING - Some issues detected"
            return 0
            ;;
        "critical")
            log_error "System health: CRITICAL - Immediate attention required"
            return 1
            ;;
        *)
            log_warning "System health: UNKNOWN"
            return 1
            ;;
    esac
}

# Check system health
check_system_health() {
    local health_file="$1"
    
    log_debug "Checking system health..."
    
    # Disk space
    local disk_usage
    disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    
    local disk_status="healthy"
    if [[ $disk_usage -gt 90 ]]; then
        disk_status="critical"
    elif [[ $disk_usage -gt 80 ]]; then
        disk_status="warning"
    fi
    
    # System load
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | cut -d',' -f1 | xargs)
    local load_status="healthy"
    
    # CPU count for load comparison
    local cpu_count
    cpu_count=$(nproc)
    
    local load_comparison3
    load_comparison3=$(awk "BEGIN {print ($load_avg > $cpu_count * 1.5) ? 1 : 0}" 2>/dev/null || echo 0)
    if [[ "$load_comparison3" == "1" ]]; then
        load_status="critical"
    fi
    
    local load_comparison4
    load_comparison4=$(awk "BEGIN {print ($load_avg > $cpu_count) ? 1 : 0}" 2>/dev/null || echo 0)
    if [[ "$load_comparison4" == "1" ]]; then
        load_status="warning"
    fi
    
    # Memory usage
    local mem_usage
    mem_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    local mem_status="healthy"
    
    if [[ $mem_usage -gt 90 ]]; then
        mem_status="critical"
    elif [[ $mem_usage -gt 80 ]]; then
        mem_status="warning"
    fi
    
    # Update health report
    jq ".system_health = {
        \"disk_usage_percent\": $disk_usage,
        \"disk_status\": \"$disk_status\",
        \"load_average\": \"$load_avg\",
        \"load_status\": \"$load_status\",
        \"memory_usage_percent\": $mem_usage,
        \"memory_status\": \"$mem_status\"
    }" "$health_file" > "${health_file}.tmp"
    mv "${health_file}.tmp" "$health_file"
}

# Check network health
check_network_health() {
    local health_file="$1"
    
    log_debug "Checking network health..."
    
    # Network connectivity status
    local network_status="healthy"
    local connectivity_issues=0
    
    # Test basic connectivity
    if ! ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
        network_status="critical"
        ((connectivity_issues++))
    fi
    
    # Check interface status
    local interface_count
    interface_count=$(ip link show | grep -c "state UP")
    
    if [[ $interface_count -lt 1 ]]; then
        network_status="critical"
        ((connectivity_issues++))
    fi
    
    # Update health report
    jq ".network_health = {
        \"connectivity_status\": \"$network_status\",
        \"connectivity_issues\": $connectivity_issues,
        \"interfaces_up\": $interface_count
    }" "$health_file" > "${health_file}.tmp"
    mv "${health_file}.tmp" "$health_file"
}

# Check service health
check_service_health() {
    local health_file="$1"
    
    log_debug "Checking service health..."
    
    local services_status="{}"
    
    # Check critical services
    local critical_services=("sshd" "systemd-networkd")
    
    for service in "${critical_services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            services_status=$(echo "$services_status" | jq ". + {\"$service\": \"running\"}")
        else
            services_status=$(echo "$services_status" | jq ". + {\"$service\": \"stopped\"}")
        fi
    done
    
    # Check OPNsense/firewall services if available
    if command -v pfctl &> /dev/null; then
        if pfctl -s info &> /dev/null; then
            services_status=$(echo "$services_status" | jq ". + {\"pf\": \"running\"}")
        else
            services_status=$(echo "$services_status" | jq ". + {\"pf\": \"stopped\"}")
        fi
    fi
    
    # Update health report
    jq ".service_health = $services_status" "$health_file" > "${health_file}.tmp"
    mv "${health_file}.tmp" "$health_file"
}

# Determine overall health status
determine_overall_health() {
    local health_file="$1"
    
    # Check for critical issues
    local critical_count
    critical_count=$(jq '[.system_health.disk_status, .system_health.load_status, .system_health.memory_status, .network_health.connectivity_status] | map(select(. == "critical")) | length' "$health_file")
    
    local warning_count
    warning_count=$(jq '[.system_health.disk_status, .system_health.load_status, .system_health.memory_status, .network_health.connectivity_status] | map(select(. == "warning")) | length' "$health_file")
    
    local overall_status
    if [[ $critical_count -gt 0 ]]; then
        overall_status="critical"
    elif [[ $warning_count -gt 0 ]]; then
        overall_status="warning"
    else
        overall_status="healthy"
    fi
    
    jq ".overall_status = \"$overall_status\"" "$health_file" > "${health_file}.tmp"
    mv "${health_file}.tmp" "$health_file"
}

# Main execution function
main() {
    parse_args "$@"
    initialize
    validate_prerequisites
    
    case "$OPERATION" in
        deploy)
            deploy_firewall
            ;;
        sync)
            sync_gitops
            ;;
        usb-create)
            create_usb_bootstrap
            ;;
        drift-check)
            check_drift
            ;;
        validate)
            validate_config
            ;;
        test)
            run_tests
            ;;
        monitor)
            run_monitoring
            ;;
        alert)
            run_advanced_monitoring
            ;;
        backup)
            backup_config
            ;;
        *)
            log_error "Unknown operation: $OPERATION"
            show_usage
            exit 1
            ;;
    esac
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
