# BrewNix Submodule Core Template

This template provides the core infrastructure and testing framework for BrewNix submodules, enabling independent development and testing.

## Structure

```text
templates/submodule-core/
├── scripts/
│   └── core/                 # Core infrastructure modules
│       ├── init.sh          # Environment initialization
│       ├── config.sh        # Configuration management
│       └── logging.sh       # Logging infrastructure
├── tests/
│   ├── core/                # Unit tests for core modules
│   │   ├── test_config.sh   # Configuration module tests
│   │   └── test_logging.sh  # Logging module tests
│   └── integration/         # Integration tests
│       └── test_deployment.sh # Basic deployment tests
├── validate-config.sh        # Configuration validation script
├── dev-setup.sh             # Development environment setup
└── local-test.sh            # Local test execution script
```

## Usage

### 1. Duplicate to a Submodule

```bash
# Copy template to target submodule
cp -r templates/submodule-core/* vendor/your-submodule/

# Or use the duplication script (when available)
./scripts/utilities/duplicate-core.sh vendor/your-submodule
```

### 2. Set Up Development Environment

```bash
cd vendor/your-submodule
./dev-setup.sh
```

This will:

- Create necessary directories (`logs`, `tmp`, `build`, `test-results`)
- Set up file permissions
- Create environment configuration (`.env`)
- Install Git hooks for validation
- Set up test environment

### 3. Validate Configuration

```bash
./validate-config.sh --config path/to/site-config.yml
```

### 4. Run Local Tests

```bash
./local-test.sh
```

This will run:

- Configuration validation
- Core module unit tests
- Integration tests
- Generate test report

## Core Modules

### init.sh

Provides environment initialization and basic utilities:

- `init_environment()` - Set up environment variables
- `ensure_directory()` - Create directories if they don't exist
- `check_dependencies()` - Verify required tools are available

### config.sh

Handles YAML configuration file parsing:

- `get_config_value()` - Extract values from YAML config files
- `validate_config()` - Validate configuration structure
- `merge_configs()` - Merge multiple configuration sources

### logging.sh

Provides structured logging with different levels:

- `log_error()` - Error messages (always shown)
- `log_warn()` - Warning messages
- `log_info()` - Informational messages
- `log_debug()` - Debug messages (only with VERBOSE=true)

## Testing Framework

### Unit Tests

- `test_config.sh` - Tests configuration loading and parsing
- `test_logging.sh` - Tests logging functionality and output

### Integration Tests

- `test_deployment.sh` - Tests deployment structure and module loading

### Test Execution

The `local-test.sh` script provides:

- Parallel test execution
- Test result reporting
- Automatic cleanup of test artifacts
- Configurable test suites

## Development Workflow

1. **Setup**: Run `./dev-setup.sh` to initialize the environment
2. **Develop**: Make changes to submodule-specific code
3. **Validate**: Run `./validate-config.sh` to check configuration
4. **Test**: Execute `./local-test.sh` to run test suites
5. **Commit**: Git hooks will automatically validate before commit

## Synchronization

To keep core modules synchronized with the main template:

```bash
# Manual sync (when sync script is available)
./tools/update-core.sh

# Or manual copy
cp ../../../scripts/core/* ./scripts/core/
```

## Customization

### Adding New Tests

1. Create test file in appropriate directory (`tests/core/` or `tests/integration/`)
2. Follow the existing test structure with descriptive function names
3. Add test to `local-test.sh` if needed

### Extending Core Modules

1. Add new functions to appropriate core module
2. Update corresponding tests
3. Update this README with new functionality

### Environment Configuration

Customize `.env` file for submodule-specific settings:

```bash
# Development settings
VERBOSE=true
DRY_RUN=false

# Logging configuration
LOG_LEVEL=INFO
LOG_FILE=logs/development.log
```

## Benefits

- **Independent Development**: Submodules can be developed and tested in isolation
- **Consistent Structure**: Standardized core functionality across all submodules
- **Automated Testing**: Built-in test framework for quality assurance
- **Easy Synchronization**: Simple process to update core modules
- **Comprehensive Validation**: Automated checks for configuration and environment

## Troubleshooting

### Common Issues

**Permission Denied**: Run `./dev-setup.sh` to fix file permissions

**Module Not Found**: Ensure core modules are properly copied and executable

**Test Failures**: Check test output for specific error messages

**Configuration Errors**: Validate YAML syntax and required fields

### Getting Help

1. Check the test output for detailed error messages
2. Review the logs in the `logs/` directory
3. Ensure all dependencies are installed
4. Verify file permissions are correct
