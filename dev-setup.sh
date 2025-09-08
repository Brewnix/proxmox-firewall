#!/bin/bash
# templates/submodule-core/dev-setup.sh - Development environment setup script

# Source core modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# In template context, modules are in root, in submodule context they're in scripts/core/
if [[ -f "${SCRIPT_DIR}/init.sh" && -f "${SCRIPT_DIR}/logging.sh" ]]; then
    source "${SCRIPT_DIR}/init.sh"
    source "${SCRIPT_DIR}/logging.sh"
elif [[ -f "${SCRIPT_DIR}/scripts/core/init.sh" && -f "${SCRIPT_DIR}/scripts/core/logging.sh" ]]; then
    source "${SCRIPT_DIR}/scripts/core/init.sh"
    source "${SCRIPT_DIR}/scripts/core/logging.sh"
else
    echo "❌ Cannot find core modules to source"
    exit 1
fi

# Setup functions
setup_directories() {
    log_info "Setting up development directories..."

    local dirs=("logs" "tmp" "build" "test-results")

    for dir in "${dirs[@]}"; do
        if [[ ! -d "$SCRIPT_DIR/$dir" ]]; then
            if mkdir -p "$SCRIPT_DIR/$dir"; then
                log_info "Created directory: $dir"
            else
                log_error "Failed to create directory: $dir"
                return 1
            fi
        else
            log_info "Directory already exists: $dir"
        fi
    done

    return 0
}

setup_permissions() {
    log_info "Setting up file permissions..."

    # Make scripts executable
    local script_dirs=("scripts" "tests")

    for dir in "${script_dirs[@]}"; do
        if [[ -d "$SCRIPT_DIR/$dir" ]]; then
            if find "$SCRIPT_DIR/$dir" -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null; then
                log_info "Made scripts executable in: $dir"
            else
                log_warn "Some scripts may not be executable in: $dir"
            fi
        fi
    done

    return 0
}

setup_environment_file() {
    log_info "Setting up environment configuration..."

    local env_file="$SCRIPT_DIR/.env"

    if [[ ! -f "$env_file" ]]; then
        cat > "$env_file" << 'EOF'
# BrewNix Development Environment Configuration
# Copy this file and customize for your development environment

# Development settings
VERBOSE=true
DRY_RUN=false

# Logging configuration
LOG_LEVEL=INFO
LOG_FILE=logs/development.log

# Test configuration
TEST_PARALLEL=true
TEST_TIMEOUT=300

# Development tools
ENABLE_DEBUG=true
ENABLE_PROFILING=false
EOF
        log_info "Created environment file: .env"
        log_info "Please review and customize the settings in .env"
    else
        log_info "Environment file already exists: .env"
    fi

    return 0
}

setup_git_hooks() {
    log_info "Setting up Git hooks..."

    local hooks_dir="$SCRIPT_DIR/.git/hooks"

    if [[ -d "$hooks_dir" ]]; then
        # Create pre-commit hook for basic validation
        cat > "$hooks_dir/pre-commit" << 'EOF'
#!/bin/bash
# Pre-commit hook for BrewNix submodule

echo "Running pre-commit validation..."

# Run basic config validation
if [[ -f "./validate-config.sh" ]]; then
    if ! ./validate-config.sh --no-env; then
        echo "❌ Configuration validation failed!"
        exit 1
    fi
fi

echo "✅ Pre-commit validation passed"
exit 0
EOF

        chmod +x "$hooks_dir/pre-commit"
        log_info "Installed pre-commit Git hook"
    else
        log_warn "Git hooks directory not found (not a Git repository?)"
    fi

    return 0
}

setup_test_environment() {
    log_info "Setting up test environment..."

    # Create test configuration
    local test_config="$SCRIPT_DIR/tests/test_config.yml"

    if [[ ! -f "$test_config" ]]; then
        cat > "$test_config" << 'EOF'
# Test configuration for BrewNix submodule
test:
  environment: "development"
  parallel: true
  timeout: 300
  coverage: false

  database:
    type: "mock"
    host: "localhost"
    port: 5432

  network:
    simulate: true
    latency: 0
    packet_loss: 0
EOF
        log_info "Created test configuration: tests/test_config.yml"
    fi

    return 0
}

# Main setup function
main() {
    local skip_dirs=false
    local skip_perms=false
    local skip_env=false
    local skip_hooks=false
    local skip_tests=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-dirs)
                skip_dirs=true
                shift
                ;;
            --skip-perms)
                skip_perms=true
                shift
                ;;
            --skip-env)
                skip_env=true
                shift
                ;;
            --skip-hooks)
                skip_hooks=true
                shift
                ;;
            --skip-tests)
                skip_tests=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Set up development environment for BrewNix submodule"
                echo ""
                echo "Options:"
                echo "  --skip-dirs     Skip directory creation"
                echo "  --skip-perms    Skip permission setup"
                echo "  --skip-env      Skip environment file creation"
                echo "  --skip-hooks    Skip Git hooks setup"
                echo "  --skip-tests    Skip test environment setup"
                echo "  -h, --help      Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    local setup_passed=true

    # Run setup steps
    if [[ "$skip_dirs" != true ]]; then
        if ! setup_directories; then
            setup_passed=false
        fi
    fi

    if [[ "$skip_perms" != true ]]; then
        if ! setup_permissions; then
            setup_passed=false
        fi
    fi

    if [[ "$skip_env" != true ]]; then
        if ! setup_environment_file; then
            setup_passed=false
        fi
    fi

    if [[ "$skip_hooks" != true ]]; then
        if ! setup_git_hooks; then
            setup_passed=false
        fi
    fi

    if [[ "$skip_tests" != true ]]; then
        if ! setup_test_environment; then
            setup_passed=false
        fi
    fi

    # Summary
    if [[ "$setup_passed" == true ]]; then
        log_info "🎉 Development environment setup completed successfully!"
        echo ""
        echo "Next steps:"
        echo "1. Review and customize .env file"
        echo "2. Run './validate-config.sh' to verify setup"
        echo "3. Run './local-test.sh' to execute tests"
        return 0
    else
        log_error "❌ Development environment setup failed!"
        return 1
    fi
}

# Run setup if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
