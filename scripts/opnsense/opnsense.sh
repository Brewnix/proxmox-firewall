#!/bin/bash
# scripts/opnsense/opnsense.sh - OPNsense firewall management

# Source core modules
source "${SCRIPT_DIR}/core/init.sh"
source "${SCRIPT_DIR}/core/config.sh"
source "${SCRIPT_DIR}/core/logging.sh"

# OPNsense configuration
OPNSENSE_HOST="${OPNSENSE_HOST:-$(get_config_value 'opnsense.host')}"
OPNSENSE_API_KEY="${OPNSENSE_API_KEY:-$(get_config_value 'opnsense.api_key')}"
OPNSENSE_API_SECRET="${OPNSENSE_API_SECRET:-$(get_config_value 'opnsense.api_secret')}"
OPNSENSE_API_URL="${OPNSENSE_API_URL:-https://${OPNSENSE_HOST}/api}"

# Initialize OPNsense module
init_opnsense() {
    if [[ -z "$OPNSENSE_HOST" || -z "$OPNSENSE_API_KEY" || -z "$OPNSENSE_API_SECRET" ]]; then
        log_error "OPNsense configuration incomplete"
        log_error "Required: host, api_key, api_secret"
        return 1
    fi

    log_info "OPNsense module initialized"
    log_debug "Host: $OPNSENSE_HOST"
    log_debug "API URL: $OPNSENSE_API_URL"
}

# Make API request to OPNsense
opnsense_api_request() {
    local method="${1:-GET}"
    local endpoint="$2"
    local data="${3:-}"

    if [[ -z "$endpoint" ]]; then
        log_error "API endpoint required"
        return 1
    fi

    local url="${OPNSENSE_API_URL}${endpoint}"
    local auth_value
    auth_value=$(echo -n "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" | base64)
    local auth_header="Authorization: Basic ${auth_value}"

    log_debug "API Request: $method $url"

    local response
    local http_code

    if [[ "$method" == "GET" ]]; then
        response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
            -H "$auth_header" \
            -H "Content-Type: application/json" \
            "$url")
    else
        response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
            -X "$method" \
            -H "$auth_header" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "$url")
    fi

    http_code=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    response=$(echo "$response" | sed -e 's/HTTPSTATUS:.*//g')

    if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
        echo "$response"
        return 0
    else
        log_error "API request failed: HTTP $http_code"
        log_debug "Response: $response"
        return 1
    fi
}

# Get firewall rules
get_firewall_rules() {
    log_info "Retrieving firewall rules..."

    local response
    response=$(opnsense_api_request "GET" "/firewall/rule/search")

    if [[ $? -eq 0 ]]; then
        echo "$response" | python3 -c "
import json
import sys
try:
    data = json.load(sys.stdin)
    if 'rows' in data:
        print('Firewall Rules:')
        for rule in data['rows']:
            print(f'  ID: {rule.get(\"id\", \"N/A\")}')
            print(f'  Description: {rule.get(\"description\", \"N/A\")}')
            print(f'  Interface: {rule.get(\"interface\", \"N/A\")}')
            print(f'  Source: {rule.get(\"source\", \"N/A\")}')
            print(f'  Destination: {rule.get(\"destination\", \"N/A\")}')
            print(f'  Action: {rule.get(\"action\", \"N/A\")}')
            print('  ---')
    else:
        print('No rules found or unexpected response format')
except Exception as e:
    print(f'Error parsing response: {e}')
" 2>/dev/null
        return 0
    else
        log_error "Failed to retrieve firewall rules"
        return 1
    fi
}

# Create firewall rule
create_firewall_rule() {
    local interface="$1"
    local source="$2"
    local destination="$3"
    local action="${4:-pass}"
    local description="${5:-Auto-created rule}"

    if [[ -z "$interface" || -z "$source" || -z "$destination" ]]; then
        log_error "Interface, source, and destination are required"
        return 1
    fi

    log_info "Creating firewall rule: $description"

    local rule_data
    rule_data=$(cat <<EOF
{
    "rule": {
        "interface": "$interface",
        "source": "$source",
        "destination": "$destination",
        "action": "$action",
        "description": "$description",
        "enabled": "1"
    }
}
EOF
)

    local response
    response=$(opnsense_api_request "POST" "/firewall/rule/add" "$rule_data")

    if [[ $? -eq 0 ]]; then
        log_info "Firewall rule created successfully"
        echo "$response"
        return 0
    else
        log_error "Failed to create firewall rule"
        return 1
    fi
}

# Delete firewall rule
delete_firewall_rule() {
    local rule_id="$1"

    if [[ -z "$rule_id" ]]; then
        log_error "Rule ID required"
        return 1
    fi

    log_info "Deleting firewall rule ID: $rule_id"

    local response
    response=$(opnsense_api_request "DELETE" "/firewall/rule/delete/${rule_id}")

    if [[ $? -eq 0 ]]; then
        log_info "Firewall rule deleted successfully"
        return 0
    else
        log_error "Failed to delete firewall rule"
        return 1
    fi
}

# Get aliases
get_aliases() {
    log_info "Retrieving firewall aliases..."

    local response
    response=$(opnsense_api_request "GET" "/firewall/alias/search")

    if [[ $? -eq 0 ]]; then
        echo "$response" | python3 -c "
import json
import sys
try:
    data = json.load(sys.stdin)
    if 'rows' in data:
        print('Firewall Aliases:')
        for alias in data['rows']:
            print(f'  Name: {alias.get(\"name\", \"N/A\")}')
            print(f'  Type: {alias.get(\"type\", \"N/A\")}')
            print(f'  Description: {alias.get(\"description\", \"N/A\")}')
            print(f'  Content: {alias.get(\"content\", \"N/A\")}')
            print('  ---')
    else:
        print('No aliases found or unexpected response format')
except Exception as e:
    print(f'Error parsing response: {e}')
" 2>/dev/null
        return 0
    else
        log_error "Failed to retrieve aliases"
        return 1
    fi
}

# Create alias
create_alias() {
    local name="$1"
    local type="$2"
    local content="$3"
    local description="${4:-Auto-created alias}"

    if [[ -z "$name" || -z "$type" || -z "$content" ]]; then
        log_error "Name, type, and content are required"
        return 1
    fi

    log_info "Creating alias: $name"

    local alias_data
    alias_data=$(cat <<EOF
{
    "alias": {
        "name": "$name",
        "type": "$type",
        "content": "$content",
        "description": "$description",
        "enabled": "1"
    }
}
EOF
)

    local response
    response=$(opnsense_api_request "POST" "/firewall/alias/add" "$alias_data")

    if [[ $? -eq 0 ]]; then
        log_info "Alias created successfully"
        echo "$response"
        return 0
    else
        log_error "Failed to create alias"
        return 1
    fi
}

# Get interfaces
get_interfaces() {
    log_info "Retrieving network interfaces..."

    local response
    response=$(opnsense_api_request "GET" "/interfaces")

    if [[ $? -eq 0 ]]; then
        echo "$response" | python3 -c "
import json
import sys
try:
    data = json.load(sys.stdin)
    print('Network Interfaces:')
    for iface_name, iface_data in data.items():
        if isinstance(iface_data, dict):
            print(f'  {iface_name}:')
            print(f'    Description: {iface_data.get(\"descr\", \"N/A\")}')
            print(f'    IPv4: {iface_data.get(\"ipaddr\", \"N/A\")}')
            print(f'    IPv6: {iface_data.get(\"ipaddrv6\", \"N/A\")}')
            print(f'    MAC: {iface_data.get(\"mac\", \"N/A\")}')
            print('  ---')
except Exception as e:
    print(f'Error parsing response: {e}')
" 2>/dev/null
        return 0
    else
        log_error "Failed to retrieve interfaces"
        return 1
    fi
}

# Apply configuration changes
apply_changes() {
    log_info "Applying configuration changes..."

    local response
    response=$(opnsense_api_request "POST" "/firewall/rule/apply")

    if [[ $? -eq 0 ]]; then
        log_info "Configuration changes applied successfully"
        return 0
    else
        log_error "Failed to apply configuration changes"
        return 1
    fi
}

# Get system status
get_system_status() {
    log_info "Retrieving system status..."

    local response
    response=$(opnsense_api_request "GET" "/core/system/status")

    if [[ $? -eq 0 ]]; then
        echo "$response" | python3 -c "
import json
import sys
try:
    data = json.load(sys.stdin)
    print('System Status:')
    print(f'  Uptime: {data.get(\"uptime\", \"N/A\")}')
    print(f'  Load Average: {data.get(\"loadavg\", \"N/A\")}')
    print(f'  Memory Usage: {data.get(\"mem_usage\", \"N/A\")}')
    print(f'  CPU Usage: {data.get(\"cpu_usage\", \"N/A\")}')
    if 'interfaces' in data:
        print('  Interfaces:')
        for iface, stats in data['interfaces'].items():
            print(f'    {iface}: {stats}')
except Exception as e:
    print(f'Error parsing response: {e}')
" 2>/dev/null
        return 0
    else
        log_error "Failed to retrieve system status"
        return 1
    fi
}

# Main OPNsense function
opnsense_main() {
    local command="$1"
    shift

    case "$command" in
        rules)
            case "${1:-list}" in
                list) get_firewall_rules ;;
                create) create_firewall_rule "$@" ;;
                delete) delete_firewall_rule "$2" ;;
                *) log_error "Unknown rules command: $1" ;;
            esac
            ;;
        aliases)
            case "${1:-list}" in
                list) get_aliases ;;
                create) create_alias "$@" ;;
                *) log_error "Unknown aliases command: $1" ;;
            esac
            ;;
        interfaces)
            get_interfaces
            ;;
        status)
            get_system_status
            ;;
        apply)
            apply_changes
            ;;
        *)
            log_error "Unknown OPNsense command: $command"
            echo "Usage: $0 opnsense <rules|aliases|interfaces|status|apply> [options]"
            return 1
            ;;
    esac
}

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_environment
    init_logging
    init_opnsense
    opnsense_main "$@"
fi
