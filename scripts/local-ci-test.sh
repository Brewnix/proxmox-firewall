#!/bin/bash
set -euo pipefail

# BrewNix Local CI Testing Script

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
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo -e "${PURPLE}=======================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}=======================================${NC}"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Global variables for tracking results
SECURITY_PASSED=false
QUALITY_PASSED=false
TEST_PASSED=false
PERFORMANCE_PASSED=false
OVERALL_PASSED=false

# Track which checks were actually run
SECURITY_RUN=false
QUALITY_RUN=false
TEST_RUN=false
PERFORMANCE_RUN=false

# Function to check if required tools are installed
check_dependencies() {
    log_step "Checking required tools..."

    local missing_tools=()

    # Check for required tools
    if ! command -v shellcheck &> /dev/null; then
        missing_tools+=("shellcheck")
    fi

    if ! command -v python3 &> /dev/null; then
        missing_tools+=("python3")
    fi

    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi

    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi

    if ! command -v git &> /dev/null; then
        missing_tools+=("git")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_warning "Missing tools: ${missing_tools[*]}"
        log_info "Install missing tools to get full functionality"
        echo
    fi
}

# Function to run security scanning
run_security_scan() {
    log_header "🔒 SECURITY SCANNING"

    local security_issues=0

    # Check for secrets and sensitive data
    log_step "Scanning for secrets and sensitive data..."

    # Common secret patterns - more specific to avoid false positives
    local secret_patterns=(
        # AWS credentials
        "aws_access_key_id.*[A-Z0-9]{20}"
        "aws_secret_access_key.*[A-Za-z0-9/+=]{40}"
        # Generic API keys (long alphanumeric strings)
        "api_key.*[A-Za-z0-9]{32,}"
        "apikey.*[A-Za-z0-9]{32,}"
        # Tokens (long strings)
        "token.*[A-Za-z0-9]{32,}"
        "bearer.*[A-Za-z0-9]{32,}"
        # Private keys
        "BEGIN.*PRIVATE.*KEY"
        "BEGIN.*RSA.*PRIVATE"
        "BEGIN.*EC.*PRIVATE"
        # SSH keys
        "ssh-rsa.*AAAA"
        "ssh-ed25519.*AAAA"
        # Database passwords (specific patterns)
        "db_password.*[A-Za-z0-9]{8,}"
        "database_password.*[A-Za-z0-9]{8,}"
        # Generic secrets (very long strings that look like secrets)
        "secret.*[A-Za-z0-9+/=]{20,}"
    )

    # Patterns to exclude (legitimate configuration)
    local exclude_patterns=(
        "example"
        "template"
        "test"
        "mock"
        "fake"
        "dummy"
        "sample"
        "default"
        "#.*password"
        "#.*secret"
        "#.*key"
        "#.*token"
        "#.*api_key"
        "ansible_.*password"
        "network_.*key"
        "wireless_.*key"
        "vpn_.*key"
        "ssl_.*key"
        "tls_.*key"
        "ca_.*key"
        "cert_.*key"
        "password.*="
        "secret.*="
        "key.*="
        "token.*="
        "api_key.*="
    )

    local found_secrets=false
    for pattern in "${secret_patterns[@]}"; do
        # Use ripgrep if available for better pattern matching, otherwise grep
        if command -v rg &> /dev/null; then
            if rg -i "$pattern" --type sh --type yaml --type yml --type json --type env . 2>/dev/null | grep -v -E "($(IFS='|'; echo "${exclude_patterns[*]}"))"; then
                log_error "🚨 Potential secret pattern found: $pattern"
                found_secrets=true
                ((security_issues++))
            fi
        else
            if grep -r -i "$pattern" --include="*.sh" --include="*.yml" --include="*.yaml" --include="*.json" --include="*.env" . 2>/dev/null | grep -v -E "($(IFS='|'; echo "${exclude_patterns[*]}"))"; then
                log_error "🚨 Potential secret pattern found: $pattern"
                found_secrets=true
                ((security_issues++))
            fi
        fi
    done

    if [[ "$found_secrets" == true ]]; then
        log_error "❌ Security violations detected - review required"
        SECURITY_PASSED=false
    else
        log_success "✅ No obvious secrets detected"
    fi

    # Check for dangerous patterns
    log_step "Scanning for dangerous patterns..."

    local dangerous_patterns=(
        "rm -rf /"
        "chmod 777"
        "curl.*|.*bash"
        "wget.*|.*bash"
        "sudo.*password"
        "curl.*-k"
        "wget.*--no-check-certificate"
    )

    # Exclude legitimate patterns in deployment/bootstrap scripts
    local exclude_patterns=(
        "bootstrap"
        "deploy"
        "github-connect"
        "StrictHostKeyChecking=no"
        "example"
        "template"
        "test"
        "mock"
        "fake"
        "dummy"
        "sample"
        "#.*ssh"
        "#.*StrictHostKeyChecking"
    )

    local found_dangerous=false
    for pattern in "${dangerous_patterns[@]}"; do
        if grep -r "$pattern" --include="*.sh" . 2>/dev/null | grep -v -E "($(IFS='|'; echo "${exclude_patterns[*]}"))"; then
            log_error "🚨 Dangerous pattern found: $pattern"
            found_dangerous=true
            ((security_issues++))
        fi
    done

    # Check for SSH with StrictHostKeyChecking=no (but exclude legitimate deployment scripts)
    if grep -r "StrictHostKeyChecking=no" --include="*.sh" . 2>/dev/null | grep -v -E "($(IFS='|'; echo "${exclude_patterns[*]}"))"; then
        log_warning "⚠️  SSH with disabled host key checking found (review recommended)"
        ((security_issues++))
    fi

    if [[ "$found_dangerous" == true ]]; then
        log_error "❌ Dangerous patterns detected"
        SECURITY_PASSED=false
    else
        log_success "✅ No dangerous patterns detected"
    fi

    # Basic file permission check
    log_step "Checking file permissions..."
    if find . -name "*.sh" -type f -not -executable 2>/dev/null | grep -v ".git/"; then
        log_warning "⚠️  Some shell scripts are not executable"
    else
        log_success "✅ Shell script permissions OK"
    fi

    if [[ $security_issues -gt 0 ]]; then
        SECURITY_PASSED=false
        log_error "Security scan failed with $security_issues issues"
    else
        SECURITY_PASSED=true
        log_success "Security scan passed"
    fi

    SECURITY_RUN=true
    echo
}

# Function to run quality gate checks
run_quality_gate() {
    # Temporarily disable set -e to allow commands to fail without exiting
    set +e

    log_header "🔍 CODE QUALITY GATE"

    local quality_issues=0

    # Shell script linting
    log_step "Running shell script linting..."
    if command -v shellcheck &> /dev/null; then
        local shellcheck_issues=0
        while IFS= read -r -d '' file; do
            if [[ -f "$file" ]]; then
                echo "Checking $file"
                # Run shellcheck but don't let it exit the script
                if shellcheck_output=$(shellcheck "$file" 2>&1); then
                    echo "✓ $file passed"
                else
                    echo "$shellcheck_output"
                    echo "✗ Issues in $file"
                    ((shellcheck_issues++))
                fi
            fi
        done < <(find . -name "*.sh" -type f -print0 2>/dev/null)

        if [[ $shellcheck_issues -gt 0 ]]; then
            log_warning "ShellCheck found issues in $shellcheck_issues files"
            ((quality_issues += shellcheck_issues))
        else
            log_success "✅ Shell script linting passed"
        fi
    else
        log_warning "⚠️  ShellCheck not installed - skipping shell linting"
    fi

    # YAML validation
    log_step "Validating YAML files..."
    if command -v python3 &> /dev/null; then
        local yaml_issues=0
        while IFS= read -r -d '' file; do
            if [[ -f "$file" ]]; then
                echo "Validating $file"
                # Run python validation but capture exit code without exiting script
                if python3 -c "
import yaml, sys
try:
    with open('$file', 'r') as f:
        data = yaml.safe_load(f)
    print('✓ Valid YAML: $file')
    sys.exit(0)
except Exception as e:
    print('✗ Invalid YAML in $file:', e)
    sys.exit(1)
" 2>/dev/null; then
                    echo "✓ Valid YAML: $file"
                else
                    echo "✗ Invalid YAML in $file"
                    ((yaml_issues++))
                fi
            fi
        done < <(find . -name "*.yml" -o -name "*.yaml" -type f -print0 2>/dev/null)

        if [[ $yaml_issues -gt 0 ]]; then
            log_error "YAML validation failed for $yaml_issues files"
            ((quality_issues += yaml_issues))
        else
            log_success "✅ YAML validation passed"
        fi
    else
        log_warning "⚠️  Python3 not available - skipping YAML validation"
    fi

    # Check for required files
    log_step "Checking for required files..."
    local required_files=("README.md")
    local missing_files=0

    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_warning "⚠️  Missing recommended file: $file"
            ((missing_files++))
        fi
    done

    if [[ $missing_files -gt 0 ]]; then
        ((quality_issues += missing_files))
    else
        log_success "✅ Required files present"
    fi

    # Check script structure
    log_step "Checking script structure..."
    local strict_mode_issues=0
    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]]; then
            # Check for bash strict mode
            if ! head -5 "$file" 2>/dev/null | grep -q "set -euo pipefail"; then
                log_warning "⚠️  $file may not use bash strict mode"
                ((strict_mode_issues++))
            fi

            # Check file length
            local lines
            lines=$(wc -l < "$file")
            if [[ $lines -gt 300 ]]; then
                log_warning "⚠️  $file is $lines lines long (consider splitting)"
            fi
        fi
    done < <(find . -name "*.sh" -type f -print0 2>/dev/null)

    if [[ $strict_mode_issues -gt 0 ]]; then
        ((quality_issues += strict_mode_issues))
    fi

    if [[ $quality_issues -gt 10 ]]; then
        log_error "❌ Too many quality issues ($quality_issues)"
        QUALITY_PASSED=false
    elif [[ $quality_issues -gt 0 ]]; then
        log_warning "⚠️  Quality issues found: $quality_issues"
        QUALITY_PASSED=true
    else
        log_success "✅ Quality gate passed"
        QUALITY_PASSED=true
    fi

    QUALITY_RUN=true
    echo

    # Re-enable set -e
    set -e
}

# Function to run test suite
run_test_suite() {
    log_header "🧪 TEST SUITE"

    # Setup environment
    log_step "Setting up test environment..."
    if [[ -f "./dev-setup.sh" ]]; then
        if [[ -x "./dev-setup.sh" ]]; then
            log_info "Running dev-setup.sh..."
            if ./dev-setup.sh; then
                log_success "✅ Development environment setup completed"
            else
                log_warning "⚠️  Development setup completed with warnings"
            fi
        else
            log_warning "⚠️  dev-setup.sh is not executable"
        fi
    else
        log_info "No dev-setup.sh found - skipping environment setup"
    fi

    # Configuration validation
    log_step "Running configuration validation..."
    if [[ -f "./validate-config.sh" ]]; then
        if [[ -x "./validate-config.sh" ]]; then
            log_info "Running validate-config.sh..."
            if ./validate-config.sh; then
                log_success "✅ Configuration validation passed"
            else
                log_warning "⚠️  Configuration validation completed with warnings"
            fi
        else
            log_warning "⚠️  validate-config.sh is not executable"
        fi
    else
        log_info "No validate-config.sh found - skipping config validation"
    fi

    # Run tests
    log_step "Running test suite..."
    local test_passed=true

    if [[ -f "./local-test.sh" ]]; then
        if [[ -x "./local-test.sh" ]]; then
            log_info "Running local-test.sh..."
            if ./local-test.sh; then
                log_success "✅ Local tests passed"
            else
                log_error "❌ Local tests failed"
                test_passed=false
            fi
        else
            log_warning "⚠️  local-test.sh is not executable"
            test_passed=false
        fi
    else
        log_warning "⚠️  No local-test.sh found"
        test_passed=false
    fi

    # Run additional test scripts if they exist
    if [[ -d "tests" ]]; then
        log_info "Running additional tests from tests/ directory..."
        local additional_tests=0
        local additional_passed=0

        while IFS= read -r -d '' test_file; do
            if [[ -x "$test_file" ]]; then
                echo "Running $test_file..."
                if "$test_file"; then
                    ((additional_passed++))
                fi
                ((additional_tests++))
            fi
        done < <(find tests -name "*.sh" -type f -print0 2>/dev/null)

        if [[ $additional_tests -gt 0 ]]; then
            log_info "Additional tests: $additional_passed/$additional_tests passed"
        fi
    fi

    TEST_PASSED=$test_passed

    if [[ "$TEST_PASSED" == true ]]; then
        log_success "✅ Test suite completed"
    else
        log_warning "⚠️  Test suite completed with issues"
    fi

    TEST_RUN=true
    echo
}

# Function to run performance benchmarking
run_performance_benchmark() {
    log_header "⚡ PERFORMANCE BENCHMARKING"

    log_step "Running performance benchmarks..."

    # Create performance report
    local report_file="local-performance-report.md"
    echo "# Local Performance Report" > "$report_file"
    echo "Generated: $(date)" >> "$report_file"
    echo "" >> "$report_file"
    echo "| Script | Execution Time | Memory Usage | Exit Code |" >> "$report_file"
    echo "|--------|----------------|--------------|-----------|" >> "$report_file"

    local performance_issues=0

    # Benchmark core scripts
    local core_scripts=("scripts/core/init.sh" "scripts/core/config.sh" "scripts/core/logging.sh" "dev-setup.sh" "local-test.sh" "validate-config.sh")

    for script in "${core_scripts[@]}"; do
        if [[ -f "$script" && -x "$script" ]]; then
            echo "Benchmarking $script..."

            # Run script with timing
            if /usr/bin/time -f "%e %M %x" bash "$script" 2>time_output.log >script_output.log 2>&1; then
                :
            fi

            local execution_time
            execution_time=$(cat time_output.log | awk '{print $1}' 2>/dev/null || echo "N/A")
            local memory_usage
            memory_usage=$(cat time_output.log | awk '{print $2}' 2>/dev/null || echo "N/A")
            local exit_code
            exit_code=$(cat time_output.log | awk '{print $3}' 2>/dev/null || echo "N/A")

            echo "| $script | ${execution_time}s | ${memory_usage}KB | $exit_code |" >> "$report_file"
            echo "✓ $script: ${execution_time}s, ${memory_usage}KB, exit: $exit_code"

            # Check for performance issues
            if [[ "$execution_time" != "N/A" && $(echo "$execution_time > 10" | bc -l 2>/dev/null) ]]; then
                log_warning "⚠️  $script took longer than 10 seconds"
                ((performance_issues++))
            fi
        fi
    done

    # Clean up temp files
    rm -f time_output.log script_output.log

    # Performance analysis
    log_step "Analyzing performance patterns..."

    # Check for performance anti-patterns
    if grep -r "sleep.*[0-9]" --include="*.sh" . 2>/dev/null | grep -v "#"; then
        log_warning "⚠️  Sleep statements found - may impact performance"
        ((performance_issues++))
    fi

    # Check for inefficient patterns
    if grep -r "for.*in.*\$\(" --include="*.sh" . 2>/dev/null; then
        log_warning "⚠️  Command substitution in loops detected - potential performance issue"
        ((performance_issues++))
    fi

    echo "" >> "$report_file"
    echo "## Performance Analysis" >> "$report_file"
    echo "- Issues found: $performance_issues" >> "$report_file"
    echo "- Report generated: $(date)" >> "$report_file"

    log_success "Performance report saved to: $report_file"

    if [[ $performance_issues -gt 0 ]]; then
        log_warning "⚠️  Performance issues found: $performance_issues"
        PERFORMANCE_PASSED=false
    else
        log_success "✅ Performance benchmarking completed"
        PERFORMANCE_PASSED=true
    fi

    PERFORMANCE_RUN=true
    echo
}

# Function to generate final report
generate_final_report() {
    log_header "📊 FINAL REPORT"

    echo "# Local CI Test Results" > local-ci-report.md
    echo "Generated: $(date)" >> local-ci-report.md
    echo "Repository: $(basename "$(pwd)")" >> local-ci-report.md
    echo "" >> local-ci-report.md

    echo "## Test Results:" >> local-ci-report.md

    # Only show results for checks that were actually run
    if [[ "$SECURITY_RUN" == true ]]; then
        echo "- 🔒 Security Scan: $([[ "$SECURITY_PASSED" == true ]] && echo "✅ PASSED" || echo "❌ FAILED")" >> local-ci-report.md
    else
        echo "- � Security Scan: ⏭️  SKIPPED" >> local-ci-report.md
    fi

    if [[ "$QUALITY_RUN" == true ]]; then
        echo "- �🔍 Quality Gate: $([[ "$QUALITY_PASSED" == true ]] && echo "✅ PASSED" || echo "❌ FAILED")" >> local-ci-report.md
    else
        echo "- 🔍 Quality Gate: ⏭️  SKIPPED" >> local-ci-report.md
    fi

    if [[ "$TEST_RUN" == true ]]; then
        echo "- 🧪 Test Suite: $([[ "$TEST_PASSED" == true ]] && echo "✅ PASSED" || echo "❌ FAILED")" >> local-ci-report.md
    else
        echo "- 🧪 Test Suite: ⏭️  SKIPPED" >> local-ci-report.md
    fi

    if [[ "$PERFORMANCE_RUN" == true ]]; then
        echo "- ⚡ Performance: $([[ "$PERFORMANCE_PASSED" == true ]] && echo "✅ PASSED" || echo "❌ FAILED")" >> local-ci-report.md
    else
        echo "- ⚡ Performance: ⏭️  SKIPPED" >> local-ci-report.md
    fi

    echo "" >> local-ci-report.md

    # Overall status - only consider checks that were actually run
    local any_run_failed=false

    if [[ "$SECURITY_RUN" == true && "$SECURITY_PASSED" == false ]]; then
        any_run_failed=true
    fi
    if [[ "$QUALITY_RUN" == true && "$QUALITY_PASSED" == false ]]; then
        any_run_failed=true
    fi
    if [[ "$TEST_RUN" == true && "$TEST_PASSED" == false ]]; then
        any_run_failed=true
    fi
    if [[ "$PERFORMANCE_RUN" == true && "$PERFORMANCE_PASSED" == false ]]; then
        any_run_failed=true
    fi

    if [[ "$any_run_failed" == false ]]; then
        OVERALL_PASSED=true
        echo "## Overall Status: ✅ ALL RUN CHECKS PASSED" >> local-ci-report.md
        echo "" >> local-ci-report.md
        echo "🎉 Ready to commit and push!" >> local-ci-report.md
    else
        OVERALL_PASSED=false
        echo "## Overall Status: ❌ ISSUES FOUND IN RUN CHECKS" >> local-ci-report.md
        echo "" >> local-ci-report.md
        echo "⚠️  Please address the issues before pushing." >> local-ci-report.md
    fi

    echo "" >> local-ci-report.md
    echo "## Recommendations:" >> local-ci-report.md

    if [[ "$SECURITY_RUN" == true && "$SECURITY_PASSED" == false ]]; then
        echo "- 🔴 **CRITICAL**: Address security vulnerabilities immediately" >> local-ci-report.md
    fi

    if [[ "$QUALITY_RUN" == true && "$QUALITY_PASSED" == false ]]; then
        echo "- 🟡 **HIGH**: Fix code quality issues" >> local-ci-report.md
    fi

    if [[ "$TEST_RUN" == true && "$TEST_PASSED" == false ]]; then
        echo "- 🟠 **MEDIUM**: Investigate test failures" >> local-ci-report.md
    fi

    if [[ "$PERFORMANCE_RUN" == true && "$PERFORMANCE_PASSED" == false ]]; then
        echo "- 🟢 **LOW**: Review performance metrics" >> local-ci-report.md
    fi

    echo "" >> local-ci-report.md
    echo "## Next Steps:" >> local-ci-report.md
    echo "1. Review detailed output above" >> local-ci-report.md
    echo "2. Fix any critical or high-priority issues" >> local-ci-report.md
    echo "3. Run 'local-ci-test.sh' again to verify fixes" >> local-ci-report.md
    echo "4. Commit and push when all checks pass" >> local-ci-report.md

    log_success "Detailed report saved to: local-ci-report.md"

    # Display summary - only show results for checks that were run
    echo
    echo "========================================"
    echo "SUMMARY"
    echo "========================================"

    if [[ "$SECURITY_RUN" == true ]]; then
        echo "Security: $([[ "$SECURITY_PASSED" == true ]] && echo "✅ PASSED" || echo "❌ FAILED")"
    else
        echo "Security: ⏭️  SKIPPED"
    fi

    if [[ "$QUALITY_RUN" == true ]]; then
        echo "Quality:  $([[ "$QUALITY_PASSED" == true ]] && echo "✅ PASSED" || echo "❌ FAILED")"
    else
        echo "Quality:  ⏭️  SKIPPED"
    fi

    if [[ "$TEST_RUN" == true ]]; then
        echo "Tests:    $([[ "$TEST_PASSED" == true ]] && echo "✅ PASSED" || echo "❌ FAILED")"
    else
        echo "Tests:    ⏭️  SKIPPED"
    fi

    if [[ "$PERFORMANCE_RUN" == true ]]; then
        echo "Performance: $([[ "$PERFORMANCE_PASSED" == true ]] && echo "✅ PASSED" || echo "❌ FAILED")"
    else
        echo "Performance: ⏭️  SKIPPED"
    fi

    echo
    echo "Overall: $([[ "$OVERALL_PASSED" == true ]] && echo "🎉 ALL RUN CHECKS PASSED" || echo "⚠️  ISSUES FOUND IN RUN CHECKS")"
    echo
    echo "Detailed report: local-ci-report.md"
    if [[ -f "local-performance-report.md" ]]; then
        echo "Performance report: local-performance-report.md"
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
BrewNix Local CI Testing Script

This script runs the same checks as the CI pipeline locally to provide immediate feedback.

USAGE:
    ./local-ci-test.sh [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -s, --security      Run only security scanning
    -q, --quality       Run only quality gate checks
    -t, --test          Run only test suite
    -p, --performance   Run only performance benchmarking
    --no-color          Disable colored output

EXAMPLES:
    ./local-ci-test.sh              # Run all checks
    ./local-ci-test.sh --security   # Run only security checks
    ./local-ci-test.sh --quality    # Run only quality checks

DEPENDENCIES:
    - shellcheck (for shell script linting)
    - python3 (for YAML validation)
    - jq (for JSON processing)
    - curl (for network checks)
    - git (for repository operations)

The script will create:
    - local-ci-report.md (detailed test results)
    - local-performance-report.md (performance metrics)

EOF
}

# Main function
main() {
    local run_security=true
    local run_quality=true
    local run_test=true
    local run_performance=true

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -s|--security)
                run_security=true
                run_quality=false
                run_test=false
                run_performance=false
                ;;
            -q|--quality)
                run_security=false
                run_quality=true
                run_test=false
                run_performance=false
                ;;
            -t|--test)
                run_security=false
                run_quality=false
                run_test=true
                run_performance=false
                ;;
            -p|--performance)
                run_security=false
                run_quality=false
                run_test=false
                run_performance=true
                ;;
            --no-color)
                RED=''
                GREEN=''
                YELLOW=''
                BLUE=''
                PURPLE=''
                CYAN=''
                NC=''
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
        shift
    done

    log_info "Starting BrewNix Local CI Testing"
    log_info "Repository: $(basename "$(pwd)")"
    log_info "Date: $(date)"

    # Check dependencies
    check_dependencies

    # Run selected checks
    if [[ "$run_security" == true ]]; then
        run_security_scan
    fi

    if [[ "$run_quality" == true ]]; then
        run_quality_gate
    fi

    if [[ "$run_test" == true ]]; then
        run_test_suite
    fi

    if [[ "$run_performance" == true ]]; then
        run_performance_benchmark
    fi

    # Generate final report
    generate_final_report

    # Exit with appropriate code
    if [[ "$OVERALL_PASSED" == true ]]; then
        log_success "🎉 All local CI checks passed!"
        exit 0
    else
        log_warning "⚠️  Local CI checks found issues. Please review and fix before pushing."
        exit 1
    fi
}

# Run main function with all arguments
main "$@"
