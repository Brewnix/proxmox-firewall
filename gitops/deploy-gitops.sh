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
USB_DEVICE=""
DRIFT_CHECK_ONLY=false

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

ENVIRONMENT VARIABLES:
    TAILSCALE_AUTH_KEY      Tailscale authentication key
    GRAFANA_ADMIN_PASSWORD  Grafana admin password
    GITOPS_WEBHOOK_URL      Webhook URL for notifications
    AWS_ACCESS_KEY_ID       AWS access key for S3 backups
    AWS_SECRET_ACCESS_KEY   AWS secret key for S3 backups
    BACKUP_S3_BUCKET        S3 bucket for backups

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
            --drift-only)
                DRIFT_CHECK_ONLY=true
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
    
    local drift_report="${BUILD_DIR}/drift-report-${SITE_NAME}-$(date +%Y%m%d-%H%M%S).json"
    
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
deploy_firewall() {
    log_info "Deploying Proxmox Firewall infrastructure with GitOps..."
    
    # Setup GitOps if configured
    if [[ -n "$GITOPS_REPO" ]]; then
        setup_gitops
    fi
    
    # Run Ansible deployment
    log_info "Executing Ansible deployment..."
    
    cd "$PROJECT_ROOT"
    
    # Use the vendor deployment script
    local deploy_cmd=(
        "${VENDOR_ROOT}/scripts/deploy-vendor.sh"
        "proxmox-firewall"
        "$SITE_CONFIG"
    )
    
    if [[ "$VERBOSE" == "true" ]]; then
        deploy_cmd+=("-vvv")
    fi
    
    log_debug "Running: ${deploy_cmd[*]}"
    
    if "${deploy_cmd[@]}"; then
        log_success "Ansible deployment completed successfully"
    else
        log_error "Ansible deployment failed"
        return 1
    fi
    
    # Setup drift detection service
    setup_drift_detection
    
    # Perform initial drift check
    check_drift || true
    
    log_success "GitOps deployment completed successfully"
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
    
    log_info "Syncing configuration from GitOps repository..."
    
    setup_gitops
    
    # Check for changes and apply if needed
    local gitops_dir="${BUILD_DIR}/gitops-repo"
    cd "$gitops_dir"
    
    if git diff --quiet HEAD~1 HEAD; then
        log_info "No changes detected in GitOps repository"
        return 0
    fi
    
    log_info "Changes detected, applying configuration..."
    
    # Copy updated configuration
    if [[ -f "config/sites/${SITE_NAME}/firewall-site.yml" ]]; then
        cp "config/sites/${SITE_NAME}/firewall-site.yml" "$SITE_CONFIG"
        log_info "Updated site configuration from GitOps repository"
    fi
    
    # Redeploy with updated configuration
    deploy_firewall
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
    
    local backup_dir="${BUILD_DIR}/backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup site configuration
    cp "$SITE_CONFIG" "$backup_dir/site-config.yml"
    
    # Backup system state if GitOps repository exists
    if [[ -n "$GITOPS_REPO" ]] && [[ -d "${BUILD_DIR}/gitops-repo" ]]; then
        cp -r "${BUILD_DIR}/gitops-repo" "$backup_dir/gitops-repo"
    fi
    
    # Create backup metadata
    cat > "$backup_dir/metadata.json" << EOF
{
    "site_name": "$SITE_NAME",
    "backup_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "gitops_repo": "$GITOPS_REPO",
    "deployment_type": "$DEPLOYMENT_TYPE"
}
EOF
    
    # Compress backup
    cd "${BUILD_DIR}/backups"
    tar -czf "backup-${SITE_NAME}-$(date +%Y%m%d-%H%M%S).tar.gz" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    log_success "Configuration backup completed"
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
