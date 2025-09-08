#!/bin/bash
# scripts/core/logging.sh - Logging functions

# Logging configuration
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_FILE="${LOG_FILE:-${BUILD_DIR}/brewnix.log}"
LOG_FORMAT="${LOG_FORMAT:-[%(level)s] %(timestamp)s - %(message)s}"

# Log levels
declare -A LOG_LEVELS=(
    [DEBUG]=0
    [INFO]=1
    [WARN]=2
    [ERROR]=3
)

# Initialize logging
init_logging() {
    # Set default log file location
    if [[ -z "$LOG_FILE" ]]; then
        # In template context, use template logs directory
        # In submodule context, use submodule logs directory
        if [[ -d "logs" ]]; then
            LOG_FILE="logs/brewnix.log"
        elif [[ -d "scripts/core" ]]; then
            # We're in a submodule, use relative path
            LOG_FILE="logs/brewnix.log"
        else
            # Fallback to current directory
            LOG_FILE="./brewnix.log"
        fi
    fi

    # Create logs directory if it doesn't exist
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || true
    fi

    # Set default log level
    if [[ -z "$LOG_LEVEL" ]]; then
        LOG_LEVEL="INFO"
    fi

    # Set default verbosity
    if [[ -z "$VERBOSE" ]]; then
        VERBOSE=false
    fi

    # Set default dry run
    if [[ -z "$DRY_RUN" ]]; then
        DRY_RUN=false
    fi

    log_info "Logging initialized - Level: $LOG_LEVEL, File: $LOG_FILE"
}

# Format log message
format_log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$LOG_FORMAT" in
        "[%(level)s] %(timestamp)s - %(message)s")
            echo "[$level] $timestamp - $message"
            ;;
        "%(timestamp)s [%(level)s] %(message)s")
            echo "$timestamp [$level] $message"
            ;;
        *)
            echo "$timestamp [$level] $message"
            ;;
    esac
}

# Check if log level should be logged
should_log() {
    local level="$1"
    local current_level="${LOG_LEVELS[$LOG_LEVEL]}"
    local message_level="${LOG_LEVELS[$level]}"

    [[ $message_level -ge $current_level ]]
}

# Log message to file and console
log_message() {
    local level="$1"
    local message="$2"

    if ! should_log "$level"; then
        return
    fi

    local formatted_message
    formatted_message=$(format_log_message "$level" "$message")

    # Log to file
    echo "$formatted_message" >> "$LOG_FILE"

    # Log to console (with color for interactive sessions)
    if [[ -t 1 ]]; then
        case "$level" in
            DEBUG) echo -e "\033[36m$formatted_message\033[0m" ;;
            INFO)  echo -e "\033[32m$formatted_message\033[0m" ;;
            WARN)  echo -e "\033[33m$formatted_message\033[0m" ;;
            ERROR) echo -e "\033[31m$formatted_message\033[0m" ;;
            *)     echo "$formatted_message" ;;
        esac
    else
        echo "$formatted_message"
    fi
}

# Debug log
log_debug() {
    log_message "DEBUG" "$*"
}

# Info log
log_info() {
    log_message "INFO" "$*"
}

# Warning log
log_warn() {
    log_message "WARN" "$*"
}

# Error log
log_error() {
    log_message "ERROR" "$*"
}

# Success log
log_success() {
    log_message "INFO" "✅ $*"
}

# Fatal error (exits script)
log_fatal() {
    log_message "ERROR" "$*"
    exit 1
}

# Log command execution
log_command() {
    local command="$*"
    log_debug "Executing: $command"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute: $command"
        return 0
    fi

    # Execute command and capture output
    local output
    local exit_code

    if [[ "$VERBOSE" == "true" ]]; then
        eval "$command"
        exit_code=$?
    else
        output=$(eval "$command" 2>&1)
        exit_code=$?
    fi

    if [[ $exit_code -ne 0 ]]; then
        log_error "Command failed (exit code: $exit_code): $command"
        if [[ "$VERBOSE" != "true" && -n "$output" ]]; then
            log_error "Command output: $output"
        fi
        return $exit_code
    else
        log_debug "Command succeeded: $command"
        if [[ "$VERBOSE" == "true" && -n "$output" ]]; then
            log_debug "Command output: $output"
        fi
        return 0
    fi
}

# Log section header
log_section() {
    local title="$*"
    local separator="=================================================================================="
    log_info ""
    log_info "$separator"
    log_info "  $title"
    log_info "$separator"
    log_info ""
}

# Log subsection header
log_subsection() {
    local title="$*"
    local separator="----------------------------------------------------------------------------------"
    log_info "$separator"
    log_info "  $title"
    log_info "$separator"
}

# Display log file location
show_log_location() {
    log_info "Log file location: $LOG_FILE"
    log_info "Log level: $LOG_LEVEL"
}
