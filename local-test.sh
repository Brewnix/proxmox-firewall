#!/bin/bash
# templates/submodule-core/local-test.sh - Local test execution script

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

# Test execution functions
run_core_tests() {
    log_info "Running core module tests..."

    local test_files=("tests/core/test_config.sh" "tests/core/test_logging.sh")
    local failed_tests=0

    for test_file in "${test_files[@]}"; do
        if [[ -f "$SCRIPT_DIR/$test_file" ]]; then
            log_info "Executing: $test_file"
            if ! bash "$SCRIPT_DIR/$test_file"; then
                log_error "Test failed: $test_file"
                ((failed_tests++))
            fi
        else
            log_warn "Test file not found: $test_file"
        fi
    done

    return $failed_tests
}

run_integration_tests() {
    log_info "Running integration tests..."

    local test_files=("tests/integration/test_deployment.sh")
    local failed_tests=0

    for test_file in "${test_files[@]}"; do
        if [[ -f "$SCRIPT_DIR/$test_file" ]]; then
            log_info "Executing: $test_file"
            if ! bash "$SCRIPT_DIR/$test_file"; then
                log_error "Integration test failed: $test_file"
                ((failed_tests++))
            fi
        else
            log_warn "Integration test file not found: $test_file"
        fi
    done

    return $failed_tests
}

run_validation_tests() {
    log_info "Running configuration validation..."

    if [[ -f "$SCRIPT_DIR/validate-config.sh" ]]; then
        if ! "$SCRIPT_DIR/validate-config.sh"; then
            log_error "Configuration validation failed"
            return 1
        fi
    else
        log_warn "Validation script not found: validate-config.sh"
    fi

    return 0
}

generate_test_report() {
    local total_tests="$1"
    local failed_tests="$2"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local report_file="$SCRIPT_DIR/test-results/report_${timestamp}.txt"

    log_info "Generating test report: $report_file"

    cat > "$report_file" << EOF
BrewNix Submodule Test Report
Generated: $(date)
=====================================

Test Summary:
- Total test suites: $total_tests
- Failed test suites: $failed_tests
- Passed test suites: $((total_tests - failed_tests))

Test Results:
EOF

    if [[ $failed_tests -eq 0 ]]; then
        echo "- ✅ All tests passed!" >> "$report_file"
    else
        echo "- ❌ $failed_tests test suite(s) failed" >> "$report_file"
    fi

    echo "" >> "$report_file"
    echo "For detailed logs, check the main log output above." >> "$report_file"

    log_info "Test report saved to: $report_file"
}

cleanup_test_artifacts() {
    log_info "Cleaning up test artifacts..."

    # Remove temporary test files
    find "$SCRIPT_DIR" -name "test_*.yml" -type f -delete 2>/dev/null || true
    find "$SCRIPT_DIR" -name "test_*.log" -type f -delete 2>/dev/null || true
    find "$SCRIPT_DIR" -name "*.tmp" -type f -delete 2>/dev/null || true

    log_info "Test cleanup completed"
}

# Main test function
main() {
    local run_core=true
    local run_integration=true
    local run_validation=true
    local generate_report=true
    local cleanup=true

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --no-core)
                run_core=false
                shift
                ;;
            --no-integration)
                run_integration=false
                shift
                ;;
            --no-validation)
                run_validation=false
                shift
                ;;
            --no-report)
                generate_report=false
                shift
                ;;
            --no-cleanup)
                cleanup=false
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Run local tests for BrewNix submodule"
                echo ""
                echo "Options:"
                echo "  --no-core         Skip core module tests"
                echo "  --no-integration  Skip integration tests"
                echo "  --no-validation   Skip configuration validation"
                echo "  --no-report       Skip test report generation"
                echo "  --no-cleanup      Skip test artifact cleanup"
                echo "  -h, --help        Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    log_info "🚀 Starting local test execution..."

    local total_test_suites=0
    local failed_test_suites=0

    # Run test suites
    if [[ "$run_validation" == true ]]; then
        ((total_test_suites++))
        if ! run_validation_tests; then
            ((failed_test_suites++))
        fi
    fi

    if [[ "$run_core" == true ]]; then
        ((total_test_suites++))
        local core_failures
        core_failures=$(run_core_tests)
        if [[ $core_failures -gt 0 ]]; then
            ((failed_test_suites++))
        fi
    fi

    if [[ "$run_integration" == true ]]; then
        ((total_test_suites++))
        local integration_failures
        integration_failures=$(run_integration_tests)
        if [[ $integration_failures -gt 0 ]]; then
            ((failed_test_suites++))
        fi
    fi

    # Generate report
    if [[ "$generate_report" == true ]]; then
        generate_test_report "$total_test_suites" "$failed_test_suites"
    fi

    # Cleanup
    if [[ "$cleanup" == true ]]; then
        cleanup_test_artifacts
    fi

    # Final summary
    echo ""
    if [[ $failed_test_suites -eq 0 ]]; then
        log_info "🎉 All $total_test_suites test suite(s) passed!"
        return 0
    else
        log_error "❌ $failed_test_suites out of $total_test_suites test suite(s) failed!"
        return 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
