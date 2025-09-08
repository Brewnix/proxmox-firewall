#!/bin/bash
# templates/submodule-core/tests/core/test_logging.sh - Logging module tests

# Source the module to test
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
# In template context, modules are in root, in submodule context they're in scripts/core/
if [[ -f "${SCRIPT_DIR}/init.sh" ]]; then
    source "${SCRIPT_DIR}/init.sh"
    source "${SCRIPT_DIR}/logging.sh"
elif [[ -f "${SCRIPT_DIR}/scripts/core/init.sh" ]]; then
    source "${SCRIPT_DIR}/scripts/core/init.sh"
    source "${SCRIPT_DIR}/scripts/core/logging.sh"
else
    echo "❌ Cannot find core modules to test"
    exit 1
fi

# Test functions
test_log_levels() {
    echo "Testing log levels..."

    # Test log_error
    echo "Testing log_error (should show ERROR prefix):"
    log_error "This is an error message"

    # Test log_warn
    echo "Testing log_warn (should show WARN prefix):"
    log_warn "This is a warning message"

    # Test log_info
    echo "Testing log_info (should show INFO prefix):"
    log_info "This is an info message"

    # Test log_debug (only if VERBOSE is set)
    echo "Testing log_debug (should show DEBUG prefix only if VERBOSE):"
    log_debug "This is a debug message"

    echo "✅ Log level tests completed"
    return 0
}

test_log_formatting() {
    echo "Testing log formatting..."

    # Test that logs include timestamps and proper formatting
    # This is more of a visual inspection test

    echo "Sample formatted log output:"
    log_info "Test message with formatting"
    log_error "Error message with formatting"
    log_warn "Warning message with formatting"

    echo "✅ Log formatting tests completed"
    return 0
}

test_log_output() {
    echo "Testing log output redirection..."

    # Test that logs can be redirected to files
    local test_log_file="${SCRIPT_DIR}/test_output.log"

    # Redirect logs to file temporarily
    exec 3>&1  # Save stdout
    exec 1>"$test_log_file"  # Redirect stdout to file

    log_info "This should go to file"
    log_error "This error should also go to file"

    exec 1>&3  # Restore stdout
    exec 3>&-  # Close fd 3

    # Check if file contains expected content
    if grep -q "This should go to file" "$test_log_file" && grep -q "This error should also go to file" "$test_log_file"; then
        echo "✅ Log output redirection test passed"
        rm -f "$test_log_file"
        return 0
    else
        echo "❌ Log output redirection test failed"
        rm -f "$test_log_file"
        return 1
    fi
}

# Main test execution
main() {
    echo "Running logging module tests..."

    local failed_tests=0

    if ! test_log_levels; then
        ((failed_tests++))
    fi

    if ! test_log_formatting; then
        ((failed_tests++))
    fi

    if ! test_log_output; then
        ((failed_tests++))
    fi

    if [[ $failed_tests -eq 0 ]]; then
        echo "✅ All logging tests passed!"
        return 0
    else
        echo "❌ $failed_tests logging test(s) failed!"
        return 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
