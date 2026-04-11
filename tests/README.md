# Unit and Static Tests

This directory contains fast, lightweight tests that don't require Docker or external services. These tests focus on configuration validation, syntax checking, and static analysis.

## Test Categories

### Configuration Validation
- YAML syntax validation for site and device configs
- Schema validation against templates
- Required field checking
- Network topology validation

### Template Testing
- Jinja2 template rendering tests
- Variable substitution validation
- Template syntax checking

### Ansible Validation
- Playbook syntax validation
- Role dependency checking
- Variable reference validation
- Task logic testing

### Terraform Validation
- HCL syntax validation
- Variable definition checking
- Resource dependency validation

## Running Tests

```bash
# Run all unit tests
python -m pytest tests/

# Run specific test category
python -m pytest tests/config/
python -m pytest tests/ansible/
python -m pytest tests/terraform/
# Greenfield Ansible/Terraform under proxmox/ansible, workloads/terraform, workloads/terraform-opnsense

# Run with coverage
python -m pytest tests/ --cov=.
```

## Test Structure

```
tests/
├── config/           # Configuration validation tests
├── ansible/          # Ansible playbook/role tests  
├── terraform/        # Terraform configuration tests
├── templates/        # Template rendering tests
└── fixtures/         # Test data and example configs
```

## Key Principles

- **Fast**: No external dependencies, Docker, or network calls
- **Static**: Tests configuration files and code without execution
- **Comprehensive**: Covers all configuration aspects
- **CI-Friendly**: Runs quickly in CI/CD pipelines

For integration testing with full system simulation, see `docker-test-framework/`. 