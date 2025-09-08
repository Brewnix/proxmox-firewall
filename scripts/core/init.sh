#!/bin/bash
# scripts/core/init.sh - Core initialization functions

# Initialize environment
init_environment() {
    # Set script configuration
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    export SCRIPT_DIR="$script_dir"

    local project_root
    project_root="$(cd "${SCRIPT_DIR}/.." && pwd)"
    export PROJECT_ROOT="$project_root"

    export BUILD_DIR="${PROJECT_ROOT}/build"
    export VENDOR_ROOT="${PROJECT_ROOT}/vendor/proxmox-firewall"

    # Create build directory
    mkdir -p "$BUILD_DIR"

    # Set PATH to include local binaries
    export PATH="${SCRIPT_DIR}/bin:${PATH}"

    # Set default environment variables
    export VERBOSE="${VERBOSE:-false}"
    export DRY_RUN="${DRY_RUN:-false}"

    log_debug "Environment initialized"
    log_debug "Project root: $PROJECT_ROOT"
    log_debug "Build directory: $BUILD_DIR"
}

# Validate prerequisites
validate_prerequisites() {
    local missing_tools=()

    # Check required tools
    for tool in ansible git python3 jq curl; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install missing tools and try again"
        return 1
    fi

    log_debug "Prerequisites validation completed"
    return 0
}

# Setup Python virtual environment if needed
setup_python_env() {
    local venv_dir="${BUILD_DIR}/venv"

    if [[ ! -d "$venv_dir" ]]; then
        log_info "Setting up Python virtual environment..."
        python3 -m venv "$venv_dir"
    fi

    # Activate virtual environment
    source "${venv_dir}/bin/activate"

    # Install required packages
    pip install --quiet -r "${PROJECT_ROOT}/requirements.txt" 2>/dev/null || true

    log_debug "Python environment ready"
}

# Cleanup function
cleanup() {
    local exit_code=$?

    # Perform cleanup tasks
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi

    # Deactivate virtual environment if active
    if [[ -n "${VIRTUAL_ENV:-}" ]]; then
        deactivate 2>/dev/null || true
    fi

    log_debug "Cleanup completed"

    exit $exit_code
}

# Set up cleanup trap
trap cleanup EXIT
