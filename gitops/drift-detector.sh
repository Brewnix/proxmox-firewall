#!/bin/bash
# gitops/drift-detector.sh - Continuous drift detection service for Proxmox Firewall
# Replaces manual configuration monitoring with automated GitOps drift detection

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENDOR_ROOT="$(cd "${PROJECT_ROOT}/.." && pwd)"

# Configuration
DRIFT_CHECK_INTERVAL="${DRIFT_CHECK_INTERVAL:-300}"  # 5 minutes
GITOPS_REPO="${GITOPS_REPO:-}"
SITE_CONFIG="${SITE_CONFIG:-}"
STATE_FILE="/var/lib/brewnix/drift-state.json"
LOG_FILE="/var/log/brewnix-drift.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
    echo -e "${BLUE}$msg${NC}" | tee -a "$LOG_FILE"
}

log_success() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1"
    echo -e "${GREEN}$msg${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1"
    echo -e "${YELLOW}$msg${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"
    echo -e "${RED}$msg${NC}" | tee -a "$LOG_FILE"
}

# Initialize drift detection
initialize_drift_detection() {
    log_info "Initializing drift detection service..."
    
    # Create directories
    mkdir -p "$(dirname "$STATE_FILE")"
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Create initial state file if it doesn't exist
    if [[ ! -f "$STATE_FILE" ]]; then
        cat > "$STATE_FILE" << EOF
{
    "last_check": "never",
    "last_sync": "never",
    "drift_detected": false,
    "check_count": 0,
    "gitops_repo": "$GITOPS_REPO",
    "site_config": "$SITE_CONFIG"
}
EOF
    fi
    
    log_success "Drift detection initialized"
}

# Load current state
load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        echo '{"last_check": "never", "drift_detected": false}'
    fi
}

# Save state
save_state() {
    local state="$1"
    echo "$state" > "$STATE_FILE"
}

# Check GitOps repository for changes
check_gitops_changes() {
    if [[ -z "$GITOPS_REPO" ]]; then
        return 0
    fi
    
    log_info "Checking GitOps repository for changes..."
    
    local gitops_dir="/tmp/gitops-check-$$"
    local changes_detected=false
    
    # Clone repository to temporary location
    if git clone "$GITOPS_REPO" "$gitops_dir" &>/dev/null; then
        cd "$gitops_dir"
        
        # Check if there are new commits since last check
        local last_sync
        last_sync=$(jq -r '.last_sync' "$STATE_FILE")
        
        if [[ "$last_sync" != "never" ]]; then
            local new_commits
            new_commits=$(git rev-list --count "${last_sync}..HEAD" 2>/dev/null || echo "0")
            
            if [[ "$new_commits" -gt 0 ]]; then
                log_info "Found $new_commits new commits in GitOps repository"
                changes_detected=true
            fi
        else
            # First time check
            log_info "First time GitOps check, considering as change"
            changes_detected=true
        fi
        
        # Cleanup
        cd /
        rm -rf "$gitops_dir"
    else
        log_error "Failed to clone GitOps repository: $GITOPS_REPO"
        return 1
    fi
    
    if [[ "$changes_detected" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Check system configuration for drift
check_system_drift() {
    log_info "Checking system configuration for drift..."
    
    local drift_detected=false
    local drift_details=""
    
    # Check if Proxmox VMs match expected configuration
    if command -v pvesh &>/dev/null; then
        # Get current VM list
        local current_vms
        current_vms=$(pvesh get /nodes/localhost/qemu --output-format json 2>/dev/null || echo "[]")
        
        # Compare with expected configuration (this would be more sophisticated in practice)
        local expected_vm_count
        expected_vm_count=$(grep -c "vm_config:" "$SITE_CONFIG" 2>/dev/null || echo "0")
        
        local actual_vm_count
        actual_vm_count=$(echo "$current_vms" | jq length)
        
        if [[ "$actual_vm_count" -ne "$expected_vm_count" ]]; then
            log_warning "VM count mismatch: expected $expected_vm_count, found $actual_vm_count"
            drift_detected=true
            drift_details="VM count mismatch"
        fi
    fi
    
    # Check firewall rules (if OPNsense is accessible)
    local opnsense_host
    opnsense_host=$(grep "firewall_management_ip:" "$SITE_CONFIG" | cut -d'"' -f2 2>/dev/null || echo "")
    
    if [[ -n "$opnsense_host" ]]; then
        if ! curl -s --connect-timeout 5 "https://$opnsense_host" &>/dev/null; then
            log_warning "Cannot reach OPNsense firewall at $opnsense_host"
            drift_detected=true
            drift_details="${drift_details:+$drift_details; }Firewall unreachable"
        fi
    fi
    
    # Check if configuration files have been modified
    if [[ -f "$SITE_CONFIG" ]]; then
        local config_mtime
        config_mtime=$(stat -c %Y "$SITE_CONFIG")
        
        local last_check
        last_check=$(jq -r '.last_check' "$STATE_FILE")
        
        if [[ "$last_check" != "never" ]]; then
            local last_check_epoch
            last_check_epoch=$(date -d "$last_check" +%s 2>/dev/null || echo "0")
            
            if [[ "$config_mtime" -gt "$last_check_epoch" ]]; then
                log_warning "Site configuration file has been modified"
                drift_detected=true
                drift_details="${drift_details:+$drift_details; }Config file modified"
            fi
        fi
    fi
    
    if [[ "$drift_detected" == "true" ]]; then
        log_warning "System drift detected: $drift_details"
        return 0
    else
        log_info "No system drift detected"
        return 1
    fi
}

# Send notification about drift
send_drift_notification() {
    local drift_type="$1"
    local details="$2"
    
    log_info "Sending drift notification..."
    
    # Send webhook notification if configured
    if [[ -n "${GITOPS_WEBHOOK_URL:-}" ]]; then
        local payload
        payload=$(cat << EOF
{
    "text": "Configuration drift detected in Proxmox Firewall",
    "attachments": [
        {
            "color": "warning",
            "fields": [
                {
                    "title": "Site",
                    "value": "$(basename "$SITE_CONFIG" .yml)",
                    "short": true
                },
                {
                    "title": "Drift Type",
                    "value": "$drift_type",
                    "short": true
                },
                {
                    "title": "Details",
                    "value": "$details",
                    "short": false
                },
                {
                    "title": "Time",
                    "value": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
                    "short": true
                }
            ]
        }
    ]
}
EOF
        )
        
        if curl -s -X POST "$GITOPS_WEBHOOK_URL" \
                -H "Content-Type: application/json" \
                -d "$payload" &>/dev/null; then
            log_success "Drift notification sent successfully"
        else
            log_error "Failed to send drift notification"
        fi
    fi
    
    # Log to syslog
    logger -t brewnix-drift "Configuration drift detected: $drift_type - $details"
}

# Perform automatic sync if enabled
auto_sync() {
    if [[ -z "$GITOPS_REPO" ]]; then
        log_info "No GitOps repository configured, skipping auto-sync"
        return 0
    fi
    
    log_info "Performing automatic sync from GitOps repository..."
    
    # Use the GitOps deployment script to sync
    if "$SCRIPT_DIR/../../../../../brewnix.sh" gitops sync; then
        log_success "Automatic sync completed successfully"
        
        # Update state with successful sync
        local current_time
        current_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        local state
        state=$(load_state)
        state=$(echo "$state" | jq --arg time "$current_time" '.last_sync = $time')
        save_state "$state"
        
        return 0
    else
        log_error "Automatic sync failed"
        return 1
    fi
}

# Main drift detection loop
run_drift_detection() {
    log_info "Starting drift detection loop..."
    
    while true; do
        local current_time
        current_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        
        local state
        state=$(load_state)
        
        # Increment check count
        local check_count
        check_count=$(echo "$state" | jq '.check_count + 1')
        state=$(echo "$state" | jq --argjson count "$check_count" '.check_count = $count')
        
        log_info "Running drift check #$check_count..."
        
        local drift_detected=false
        local drift_type=""
        local drift_details=""
        
        # Check GitOps repository for changes
        if check_gitops_changes; then
            log_warning "GitOps repository changes detected"
            drift_detected=true
            drift_type="gitops"
            drift_details="New commits in GitOps repository"
            
            # Perform automatic sync
            if auto_sync; then
                drift_details="$drift_details (auto-synced successfully)"
            else
                drift_details="$drift_details (auto-sync failed)"
            fi
        fi
        
        # Check system configuration for drift
        if check_system_drift; then
            drift_detected=true
            if [[ -n "$drift_type" ]]; then
                drift_type="$drift_type,system"
                drift_details="$drift_details; System configuration drift"
            else
                drift_type="system"
                drift_details="System configuration drift detected"
            fi
        fi
        
        # Update state
        state=$(echo "$state" | jq --arg time "$current_time" '.last_check = $time')
        state=$(echo "$state" | jq --argjson detected "$drift_detected" '.drift_detected = $detected')
        save_state "$state"
        
        # Send notification if drift detected
        if [[ "$drift_detected" == "true" ]]; then
            send_drift_notification "$drift_type" "$drift_details"
        else
            log_success "No drift detected"
        fi
        
        # Wait for next check
        log_info "Waiting $DRIFT_CHECK_INTERVAL seconds until next check..."
        sleep "$DRIFT_CHECK_INTERVAL"
    done
}

# Handle signals for graceful shutdown
cleanup() {
    log_info "Drift detection service shutting down..."
    exit 0
}

trap cleanup SIGTERM SIGINT

# Usage information
show_usage() {
    cat << EOF
Brewnix Drift Detection Service for Proxmox Firewall

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --interval SECONDS    Drift check interval (default: 300)
    --gitops-repo URL     GitOps repository URL
    --site-config FILE    Site configuration file path
    --daemon              Run as daemon (continuous monitoring)
    --check-once          Perform single drift check and exit
    --help                Show this help message

ENVIRONMENT VARIABLES:
    DRIFT_CHECK_INTERVAL  Check interval in seconds (default: 300)
    GITOPS_REPO          GitOps repository URL
    SITE_CONFIG          Site configuration file path
    GITOPS_WEBHOOK_URL   Webhook URL for notifications

EXAMPLES:
    # Run continuous drift detection
    $0 --daemon --gitops-repo https://github.com/org/config.git --site-config /path/to/site.yml
    
    # Single drift check
    $0 --check-once --site-config /path/to/site.yml

EOF
}

# Parse command line arguments
parse_args() {
    local daemon_mode=false
    local check_once=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --interval)
                DRIFT_CHECK_INTERVAL="$2"
                shift 2
                ;;
            --gitops-repo)
                GITOPS_REPO="$2"
                shift 2
                ;;
            --site-config)
                SITE_CONFIG="$2"
                shift 2
                ;;
            --daemon)
                daemon_mode=true
                shift
                ;;
            --check-once)
                check_once=true
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
                log_error "Unexpected argument: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate configuration
    if [[ -n "$SITE_CONFIG" && ! -f "$SITE_CONFIG" ]]; then
        log_error "Site configuration file not found: $SITE_CONFIG"
        exit 1
    fi
    
    # Run appropriate mode
    if [[ "$check_once" == "true" ]]; then
        initialize_drift_detection
        local drift_detected=false
        
        if check_gitops_changes || check_system_drift; then
            drift_detected=true
        fi
        
        if [[ "$drift_detected" == "true" ]]; then
            log_warning "Drift detected"
            exit 1
        else
            log_success "No drift detected"
            exit 0
        fi
    elif [[ "$daemon_mode" == "true" ]]; then
        initialize_drift_detection
        run_drift_detection
    else
        show_usage
        exit 1
    fi
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_args "$@"
fi
