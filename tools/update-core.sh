#!/bin/bash
# templates/submodule-core/tools/update-core.sh - Sync core modules from main template

# Source core modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# In submodule context, modules are in scripts/core/ relative to the submodule root
if [[ -f "${SCRIPT_DIR}/../scripts/core/init.sh" && -f "${SCRIPT_DIR}/../scripts/core/config.sh" && -f "${SCRIPT_DIR}/../scripts/core/logging.sh" ]]; then
    source "${SCRIPT_DIR}/../scripts/core/init.sh"
    source "${SCRIPT_DIR}/../scripts/core/config.sh"
    source "${SCRIPT_DIR}/../scripts/core/logging.sh"
else
    echo "❌ Cannot find core modules to source from: ${SCRIPT_DIR}"
    echo "Expected path: ${SCRIPT_DIR}/../scripts/core/"
    exit 1
fi

# Configuration
TEMPLATE_CORE_DIR=""
SUBMODULE_CORE_DIR="./scripts/core"
DRY_RUN=false
VERBOSE=false

# Initialize synchronization
init_sync() {
    if [[ "$VERBOSE" == true ]]; then
        log_info "Core synchronization module initialized"
    fi

    # Determine template core directory based on context
    if [[ -d "../../../scripts/core" ]]; then
        # We're in a submodule, template is two levels up
        TEMPLATE_CORE_DIR="../../../scripts/core"
    elif [[ -d "../../scripts/core" ]]; then
        # We're in template context
        TEMPLATE_CORE_DIR="../../scripts/core"
    else
        log_error "Cannot determine template core directory location"
        exit 1
    fi

    if [[ ! -d "$TEMPLATE_CORE_DIR" ]]; then
        log_error "Template core directory not found: $TEMPLATE_CORE_DIR"
        exit 1
    fi

    if [[ ! -d "$SUBMODULE_CORE_DIR" ]]; then
        log_error "Submodule core directory not found: $SUBMODULE_CORE_DIR"
        exit 1
    fi

    if [[ "$VERBOSE" == true ]]; then
        log_info "Template core directory: $TEMPLATE_CORE_DIR"
        log_info "Submodule core directory: $SUBMODULE_CORE_DIR"
    fi
}

# Get list of core files to sync
get_core_files() {
    local core_files=(
        "init.sh"
        "config.sh"
        "logging.sh"
    )

    echo "${core_files[@]}"
}

# Backup current core files
backup_core_files() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="./scripts/core/backup_${timestamp}"

    log_info "Creating backup of current core files"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create backup: $backup_dir"
        return 0
    fi

    mkdir -p "$backup_dir"

    local core_files
    core_files=$(get_core_files)

    for file in $core_files; do
        local src_file="${SUBMODULE_CORE_DIR}/${file}"
        local dst_file="${backup_dir}/${file}"

        if [[ -f "$src_file" ]]; then
            cp "$src_file" "$dst_file"
            log_info "Backed up: $file"
        else
            log_warn "Source file not found for backup: $src_file"
        fi
    done

    echo "$backup_dir"
}

# Sync core files from template
sync_core_files() {
    log_info "Synchronizing core files from template"

    local core_files
    core_files=$(get_core_files)

    for file in $core_files; do
        local src_file="${TEMPLATE_CORE_DIR}/${file}"
        local dst_file="${SUBMODULE_CORE_DIR}/${file}"

        if [[ ! -f "$src_file" ]]; then
            log_error "Template file not found: $src_file"
            continue
        fi

        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY RUN] Would sync: $src_file -> $dst_file"
        else
            cp "$src_file" "$dst_file"
            chmod +x "$dst_file" 2>/dev/null || true
            log_info "Synced: $file"
        fi
    done
}

# Sync test files
sync_test_files() {
    log_info "Synchronizing test files from template"

    # Sync core test files
    local template_tests_dir="${TEMPLATE_CORE_DIR}/../tests/core"
    local submodule_tests_dir="./tests/core"

    if [[ ! -d "$template_tests_dir" ]]; then
        log_warn "Template tests directory not found: $template_tests_dir"
        return 0
    fi

    if [[ ! -d "$submodule_tests_dir" ]]; then
        log_warn "Submodule tests directory not found: $submodule_tests_dir"
        return 0
    fi

    local test_files=(
        "test_config.sh"
        "test_logging.sh"
    )

    for file in "${test_files[@]}"; do
        local src_file="${template_tests_dir}/${file}"
        local dst_file="${submodule_tests_dir}/${file}"

        if [[ ! -f "$src_file" ]]; then
            log_warn "Template test file not found: $src_file"
            continue
        fi

        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY RUN] Would sync test: $src_file -> $dst_file"
        else
            cp "$src_file" "$dst_file"
            chmod +x "$dst_file" 2>/dev/null || true
            log_info "Synced test: $file"
        fi
    done
}

# Sync development tools
sync_dev_tools() {
    log_info "Synchronizing development tools from template"

    local template_root=""
    if [[ -d "../../../templates/submodule-core" ]]; then
        template_root="../../../templates/submodule-core"
    elif [[ -d "../../templates/submodule-core" ]]; then
        template_root="../../templates/submodule-core"
    else
        log_warn "Cannot determine template root directory"
        return 0
    fi

    local dev_files=(
        "validate-config.sh"
        "dev-setup.sh"
        "local-test.sh"
    )

    for file in "${dev_files[@]}"; do
        local src_file="${template_root}/${file}"
        local dst_file="./${file}"

        if [[ ! -f "$src_file" ]]; then
            log_warn "Template dev file not found: $src_file"
            continue
        fi

        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY RUN] Would sync dev tool: $src_file -> $dst_file"
        else
            cp "$src_file" "$dst_file"
            chmod +x "$dst_file" 2>/dev/null || true
            log_info "Synced dev tool: $file"
        fi
    done
}

# Verify synchronization
verify_sync() {
    log_info "Verifying synchronization integrity"

    local core_files
    core_files=$(get_core_files)
    local missing_files=()
    local sync_errors=()

    for file in $core_files; do
        local submodule_file="${SUBMODULE_CORE_DIR}/${file}"
        local template_file="${TEMPLATE_CORE_DIR}/${file}"

        if [[ ! -f "$submodule_file" ]]; then
            missing_files+=("$file")
            continue
        fi

        # Check if files are different (basic check)
        if [[ -f "$template_file" ]] && [[ -f "$submodule_file" ]]; then
            local template_size
            local submodule_size
            template_size=$(stat -c%s "$template_file" 2>/dev/null || stat -f%z "$template_file" 2>/dev/null || echo "0")
            submodule_size=$(stat -c%s "$submodule_file" 2>/dev/null || stat -f%z "$submodule_file" 2>/dev/null || echo "0")

            if [[ "$template_size" != "$submodule_size" ]]; then
                sync_errors+=("$file (size mismatch)")
            fi
        fi
    done

    if [[ ${#missing_files[@]} -gt 0 ]]; then
        log_error "Missing files after sync:"
        for file in "${missing_files[@]}"; do
            log_error "  - $file"
        done
        return 1
    fi

    if [[ ${#sync_errors[@]} -gt 0 ]]; then
        log_warn "Sync verification issues:"
        for error in "${sync_errors[@]}"; do
            log_warn "  - $error"
        done
    fi

    log_info "✅ Synchronization verification completed"
    return 0
}

# Generate sync report
generate_sync_report() {
    local backup_dir="$1"
    local start_time="$2"
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local report_file="./sync_report_${timestamp}.txt"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would generate report: $report_file"
        return 0
    fi

    cat > "$report_file" << EOF
BrewNix Core Synchronization Report
Generated: $(date)
Duration: ${duration} seconds
=====================================

Synchronization Details:
- Template Core Directory: $TEMPLATE_CORE_DIR
- Submodule Core Directory: $SUBMODULE_CORE_DIR
- Backup Directory: $backup_dir

Synchronized Files:
- Core Infrastructure:
  - scripts/core/init.sh
  - scripts/core/config.sh
  - scripts/core/logging.sh

- Test Framework:
  - tests/core/test_config.sh
  - tests/core/test_logging.sh

- Development Tools:
  - validate-config.sh
  - dev-setup.sh
  - local-test.sh

Next Steps:
1. Test the synchronized core modules: ./local-test.sh
2. Validate configuration: ./validate-config.sh
3. Check for any breaking changes in your submodule code

For detailed documentation, see README.md
EOF

    log_info "Synchronization report saved: $report_file"
}

# Main synchronization function
sync_core_modules() {
    local start_time
    start_time=$(date +%s)

    log_section "Starting core module synchronization"

    # Initialize
    init_sync

    # Create backup
    local backup_dir
    backup_dir=$(backup_core_files)

    # Sync files
    sync_core_files
    sync_test_files
    sync_dev_tools

    # Verify
    if ! verify_sync; then
        log_error "Synchronization verification failed"
        return 1
    fi

    # Generate report
    generate_sync_report "$backup_dir" "$start_time"

    log_success "✅ Core module synchronization completed successfully!"
    log_info ""
    log_info "Backup location: $backup_dir"
    log_info ""
    log_info "Next steps:"
    log_info "  ./local-test.sh"
    log_info "  ./validate-config.sh"

    return 0
}

# Main execution
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Synchronize core modules from main template to submodule"
                echo ""
                echo "Options:"
                echo "  --dry-run         Show what would be done without executing"
                echo "  --verbose, -v     Enable verbose output"
                echo "  -h, --help        Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0"
                echo "  $0 --dry-run"
                echo "  $0 --verbose"
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                exit 1
                ;;
        esac
    done

    # Perform synchronization
    if sync_core_modules; then
        log_success "Synchronization completed successfully"
        exit 0
    else
        log_error "Synchronization failed"
        exit 1
    fi
}

# Run sync if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
