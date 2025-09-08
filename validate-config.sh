#!/bin/bash
# templates/submodule-core/validate-config.sh - Configuration validation script

# Source core modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# In template context, modules are in root, in submodule context they're in scripts/core/
if [[ -f "${SCRIPT_DIR}/init.sh" && -f "${SCRIPT_DIR}/config.sh" && -f "${SCRIPT_DIR}/logging.sh" ]]; then
    source "${SCRIPT_DIR}/init.sh"
    source "${SCRIPT_DIR}/config.sh"
    source "${SCRIPT_DIR}/logging.sh"
elif [[ -f "${SCRIPT_DIR}/scripts/core/init.sh" && -f "${SCRIPT_DIR}/scripts/core/config.sh" && -f "${SCRIPT_DIR}/scripts/core/logging.sh" ]]; then
    source "${SCRIPT_DIR}/scripts/core/init.sh"
    source "${SCRIPT_DIR}/scripts/core/config.sh"
    source "${SCRIPT_DIR}/scripts/core/logging.sh"
else
    echo "❌ Cannot find core modules to source"
    exit 1
fi

# Validation functions
validate_site_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi

    log_info "Validating site configuration: $config_file"

    # Check required fields
    local required_fields=("site.name" "site.description" "site.network.prefix")

    for field in "${required_fields[@]}"; do
        if ! get_config_value "$field" "$config_file" >/dev/null 2>&1; then
            log_error "Missing required configuration field: $field"
            return 1
        fi
    done

    log_info "✅ Site configuration validation passed"
    return 0
}

validate_environment() {
    log_info "Validating development environment..."

    # Check for required tools
    local required_tools=("bash" "grep" "sed" "awk")

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "Required tool not found: $tool"
            return 1
        fi
    done

    # Check for required directories
    local required_dirs=("scripts" "config" "vendor")

    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$SCRIPT_DIR/$dir" ]]; then
            log_error "Required directory not found: $dir"
            return 1
        fi
    done

    log_info "✅ Environment validation passed"
    return 0
}

validate_core_modules() {
    log_info "Validating core modules..."

    # Check that core module files exist and are executable
    local core_files=("scripts/core/init.sh" "scripts/core/config.sh" "scripts/core/logging.sh")

    for file in "${core_files[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$file" ]]; then
            log_error "Core module file not found: $file"
            return 1
        fi

        if [[ ! -x "$SCRIPT_DIR/$file" ]]; then
            log_warn "Core module file not executable: $file"
            # Try to make it executable
            if chmod +x "$SCRIPT_DIR/$file"; then
                log_info "Made $file executable"
            else
                log_error "Failed to make $file executable: $file"
                return 1
            fi
        fi
    done

    log_info "✅ Core modules validation passed"
    return 0
}

# Main validation function
main() {
    local config_file=""
    local validate_env=true
    local validate_core=true

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config|-c)
                config_file="$2"
                shift 2
                ;;
            --no-env)
                validate_env=false
                shift
                ;;
            --no-core)
                validate_core=false
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Validate configuration and environment for BrewNix submodule"
                echo ""
                echo "Options:"
                echo "  -c, --config FILE    Validate specific site configuration file"
                echo "  --no-env            Skip environment validation"
                echo "  --no-core           Skip core modules validation"
                echo "  -h, --help          Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    local validation_passed=true

    # Run validations
    if [[ "$validate_env" == true ]]; then
        if ! validate_environment; then
            validation_passed=false
        fi
    fi

    if [[ "$validate_core" == true ]]; then
        if ! validate_core_modules; then
            validation_passed=false
        fi
    fi

    if [[ -n "$config_file" ]]; then
        if ! validate_site_config "$config_file"; then
            validation_passed=false
        fi
    fi

    # Summary
    if [[ "$validation_passed" == true ]]; then
        log_info "🎉 All validations passed!"
        return 0
    else
        log_error "❌ Some validations failed!"
        return 1
    fi
}

# Run validation if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
