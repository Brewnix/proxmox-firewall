#!/bin/bash
# scripts/core/config.sh - Configuration management functions

# Initialize configuration data
CONFIG_DATA=""

# Load configuration from file
load_config() {
    local config_file="${1:-${PROJECT_ROOT}/config.yml}"

    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi

    # Load YAML configuration using Python
    if command -v python3 &> /dev/null; then
        CONFIG_DATA=$(python3 -c "
import yaml
import sys
try:
    with open('$config_file', 'r') as f:
        data = yaml.safe_load(f)
        print(yaml.dump(data, default_flow_style=False))
except Exception as e:
    print('ERROR:', str(e), file=sys.stderr)
    sys.exit(1)
" 2>/dev/null)

        if [[ $? -ne 0 ]]; then
            log_error "Failed to parse configuration file: $config_file"
            return 1
        fi
    else
        log_error "Python3 required for configuration parsing"
        return 1
    fi

    log_debug "Configuration loaded from: $config_file"
}

# Get configuration value
get_config_value() {
    local key="$1"
    local default="${2:-}"

    if [[ -z "$CONFIG_DATA" ]]; then
        echo "$default"
        return
    fi

    # Extract value using Python
    local value
    value=$(python3 -c "
import yaml
import sys
try:
    data = yaml.safe_load('$CONFIG_DATA')
    keys = '$key'.split('.')
    current = data
    for k in keys:
        if isinstance(current, dict) and k in current:
            current = current[k]
        else:
            print('', end='')
            sys.exit(0)
    print(current if current is not None else '')
except:
    print('', end='')
" 2>/dev/null)

    echo "${value:-$default}"
}

# Validate configuration
validate_config() {
    local required_keys=("network.prefix" "sites" "devices")

    for key in "${required_keys[@]}"; do
        if [[ -z "$(get_config_value "$key")" ]]; then
            log_error "Missing required configuration key: $key"
            return 1
        fi
    done

    log_debug "Configuration validation passed"
    return 0
}

# Save configuration to file
save_config() {
    local config_file="${1:-${PROJECT_ROOT}/config.yml}"
    local backup_file
    backup_file="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"

    # Create backup
    if [[ -f "$config_file" ]]; then
        cp "$config_file" "$backup_file"
        log_debug "Configuration backup created: $backup_file"
    fi

    # Save configuration
    if echo "$CONFIG_DATA" > "$config_file"; then
        log_info "Configuration saved to: $config_file"
        return 0
    else
        log_error "Failed to save configuration"
        return 1
    fi
}

# Update configuration value
update_config_value() {
    local key="$1"
    local value="$2"

    if [[ -z "$CONFIG_DATA" ]]; then
        log_error "No configuration loaded"
        return 1
    fi

    # Update value using Python
    CONFIG_DATA=$(python3 -c "
import yaml
import sys
try:
    data = yaml.safe_load('$CONFIG_DATA')
    keys = '$key'.split('.')
    current = data
    for k in keys[:-1]:
        if not isinstance(current, dict):
            current = {}
        if k not in current:
            current[k] = {}
        current = current[k]
    current[keys[-1]] = '$value'
    print(yaml.dump(data, default_flow_style=False))
except Exception as e:
    print('ERROR:', str(e), file=sys.stderr)
    sys.exit(1)
" 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        log_error "Failed to update configuration value: $key"
        return 1
    fi

    log_debug "Configuration updated: $key = $value"
}

# Get site configuration
get_site_config() {
    local site_name="$1"

    if [[ -z "$site_name" ]]; then
        log_error "Site name required"
        return 1
    fi

    local site_config
    site_config=$(get_config_value "sites.$site_name")

    if [[ -z "$site_config" ]]; then
        log_error "Site not found in configuration: $site_name"
        return 1
    fi

    echo "$site_config"
}

# List all sites
list_sites() {
    get_config_value "sites" | python3 -c "
import yaml
import sys
try:
    data = yaml.safe_load(sys.stdin.read())
    if isinstance(data, dict):
        for site in data.keys():
            print(site)
except:
    pass
" 2>/dev/null
}
