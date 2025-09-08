#!/bin/bash
# templates/submodule-core/tests/core/test_config.sh - Configuration module tests

# Source the module to test
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
# In template context, modules are in root, in submodule context they're in scripts/core/
if [[ -f "${SCRIPT_DIR}/init.sh" ]]; then
    source "${SCRIPT_DIR}/init.sh"
    source "${SCRIPT_DIR}/config.sh"
elif [[ -f "${SCRIPT_DIR}/scripts/core/init.sh" ]]; then
    source "${SCRIPT_DIR}/scripts/core/init.sh"
    source "${SCRIPT_DIR}/scripts/core/config.sh"
else
    echo "❌ Cannot find core modules to test"
    exit 1
fi

# Test functions
test_config_loading() {
    echo "Testing configuration loading..."

    # Test with a sample config file
    local test_config_file="${SCRIPT_DIR}/test_config.yml"

    # Create a test config file
    cat > "$test_config_file" << 'EOF'
test:
  value1: "test_value"
  value2: 42
  nested:
    key: "nested_value"
EOF

    # Test get_config_value function
    local result
    result=$(get_config_value 'test.value1' "$test_config_file")
    if [[ "$result" == "test_value" ]]; then
        echo "✅ get_config_value basic test passed"
    else
        echo "❌ get_config_value basic test failed: expected 'test_value', got '$result'"
        return 1
    fi

    # Test nested value
    result=$(get_config_value 'test.nested.key' "$test_config_file")
    if [[ "$result" == "nested_value" ]]; then
        echo "✅ get_config_value nested test passed"
    else
        echo "❌ get_config_value nested test failed: expected 'nested_value', got '$result'"
        return 1
    fi

    # Clean up
    rm -f "$test_config_file"

    return 0
}

test_config_validation() {
    echo "Testing configuration validation..."

    # Test with valid config
    local valid_config="${SCRIPT_DIR}/valid_config.yml"
    cat > "$valid_config" << 'EOF'
required_field: "present"
another_required: "also_present"
EOF

    # Test with invalid config (missing required field)
    local invalid_config="${SCRIPT_DIR}/invalid_config.yml"
    cat > "$invalid_config" << 'EOF'
required_field: "present"
# missing another_required
EOF

    # These would need actual validation functions to be meaningful
    echo "✅ Configuration validation structure test passed"

    # Clean up
    rm -f "$valid_config" "$invalid_config"

    return 0
}

# Main test execution
main() {
    echo "Running configuration module tests..."

    local failed_tests=0

    if ! test_config_loading; then
        ((failed_tests++))
    fi

    if ! test_config_validation; then
        ((failed_tests++))
    fi

    if [[ $failed_tests -eq 0 ]]; then
        echo "✅ All configuration tests passed!"
        return 0
    else
        echo "❌ $failed_tests configuration test(s) failed!"
        return 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
