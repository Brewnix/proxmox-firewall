#!/bin/bash
# templates/submodule-core/tests/integration/test_deployment.sh - Basic deployment integration tests

# Source required modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
# In template context, modules are in root, in submodule context they're in scripts/core/
if [[ -f "${SCRIPT_DIR}/init.sh" ]]; then
    source "${SCRIPT_DIR}/init.sh"
    source "${SCRIPT_DIR}/config.sh"
    source "${SCRIPT_DIR}/logging.sh"
elif [[ -f "${SCRIPT_DIR}/scripts/core/init.sh" ]]; then
    source "${SCRIPT_DIR}/scripts/core/init.sh"
    source "${SCRIPT_DIR}/scripts/core/config.sh"
    source "${SCRIPT_DIR}/scripts/core/logging.sh"
else
    echo "❌ Cannot find core modules to test"
    exit 1
fi

# Test functions
test_deployment_structure() {
    echo "Testing deployment structure validation..."

    # Test that required directories exist
    local required_dirs=("scripts" "config" "vendor")

    for dir in "${required_dirs[@]}"; do
        if [[ -d "$SCRIPT_DIR/../../$dir" ]]; then
            echo "✅ Required directory '$dir' exists"
        else
            echo "❌ Required directory '$dir' missing"
            return 1
        fi
    done

    return 0
}

test_config_file_validation() {
    echo "Testing configuration file validation..."

    # Create a test site configuration
    local test_site_config="${SCRIPT_DIR}/test_site.yml"

    cat > "$test_site_config" << 'EOF'
site:
  name: "test_site"
  description: "Test site for integration testing"
  network:
    prefix: "192.168.1.0/24"
  devices: []
EOF

    # Test that the config can be loaded
    if get_config_value 'site.name' "$test_site_config" >/dev/null 2>&1; then
        echo "✅ Test configuration file loads successfully"
    else
        echo "❌ Test configuration file failed to load"
        rm -f "$test_site_config"
        return 1
    fi

    # Clean up
    rm -f "$test_site_config"
    return 0
}

test_environment_setup() {
    echo "Testing environment setup..."

    # Test that basic environment variables are set
    if [[ -n "$SCRIPT_DIR" ]]; then
        echo "✅ SCRIPT_DIR environment variable is set"
    else
        echo "❌ SCRIPT_DIR environment variable is not set"
        return 1
    fi

    # Test that PROJECT_ROOT is accessible
    if [[ -d "$SCRIPT_DIR/../.." ]]; then
        echo "✅ Project root directory is accessible"
    else
        echo "❌ Project root directory is not accessible"
        return 1
    fi

    return 0
}

test_module_loading() {
    echo "Testing module loading..."

    # Test that core modules can be sourced without errors
    if source "${SCRIPT_DIR}/init.sh" 2>/dev/null && source "${SCRIPT_DIR}/config.sh" 2>/dev/null && source "${SCRIPT_DIR}/logging.sh" 2>/dev/null; then
        echo "✅ Core modules load without errors"
    else
        echo "❌ Core modules failed to load"
        return 1
    fi

    return 0
}

# Main test execution
main() {
    echo "Running deployment integration tests..."

    local failed_tests=0

    if ! test_deployment_structure; then
        ((failed_tests++))
    fi

    if ! test_config_file_validation; then
        ((failed_tests++))
    fi

    if ! test_environment_setup; then
        ((failed_tests++))
    fi

    if ! test_module_loading; then
        ((failed_tests++))
    fi

    if [[ $failed_tests -eq 0 ]]; then
        echo "✅ All deployment integration tests passed!"
        return 0
    else
        echo "❌ $failed_tests deployment integration test(s) failed!"
        return 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
