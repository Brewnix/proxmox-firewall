# Contributing to Proxmox Firewall

Thank you for your interest in contributing to the Proxmox Firewall project! This document provides guidelines and information for contributors.

## 🚀 Quick Start for Contributors

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/brewnix/proxmox-firewall.git
   cd proxmox-firewall
   ```
3. **Create a branch** for your feature:
   ```bash
   git checkout -b feature/your-feature-name
   ```
4. **Set up development environment**:
   ```bash
   cp env.example .env
   ./deployment/scripts/prerequisites.sh
   ```

## 🔧 Development Environment

### Prerequisites

- **OS**: Ubuntu 20.04+ or similar Linux distribution
- **Resources**: 8GB+ RAM, 50GB+ storage
- **Tools**: Git, Python 3.8+, Ansible 2.9+, Terraform 1.0+

### Setup Development Environment

```bash
# Install development dependencies
./deployment/scripts/prerequisites.sh

# Install pre-commit hooks (recommended)
pip install pre-commit
pre-commit install

# Run security audit to ensure safe setup
./common/scripts/security_audit.sh

# Run tests to verify setup
./validate-config.sh
```

### Docker Test Environment

For testing without physical hardware:

```bash
cd docker-test-framework
./run-integration-tests.sh -t example
```

## 📝 Types of Contributions

### 🐛 Bug Reports

Before creating a bug report:
- Search existing issues to avoid duplicates
- Test with the latest version
- Use the Docker test environment to reproduce

**Good bug reports include:**
- Clear, descriptive title
- Steps to reproduce the issue
- Expected vs actual behavior
- Environment details (OS, versions, hardware)
- Relevant logs or configuration files
- Screenshots/terminal output if applicable

### ✨ Feature Requests

Before submitting a feature request:
- Check if it aligns with project goals
- Search existing issues and discussions
- Consider if it could be implemented as a plugin/extension

**Good feature requests include:**
- Clear description of the problem it solves
- Proposed solution or approach
- Use cases and examples
- Consideration of implementation complexity

### 🔧 Code Contributions

We welcome contributions for:
- **New hardware support** (CPU types, network interfaces)
- **VPN providers** (alternative to Tailscale)
- **Monitoring integrations** (Prometheus, Grafana, etc.)
- **Security enhancements** (additional IDS/IPS rules)
- **Automation improvements** (better error handling, recovery)
- **Documentation** (guides, examples, translations)

## 🏗️ Development Guidelines

### Code Style

**Ansible Playbooks:**
- Use descriptive task names
- Add `tags` for selective execution
- Include error handling with `block`/`rescue`
- Use `ansible-lint` for validation

**Terraform:**
- Use consistent variable naming
- Add descriptions to all variables
- Include examples in comments
- Use `terraform fmt` for formatting

**Python/Shell Scripts:**
- Follow PEP 8 for Python
- Use `set -euo pipefail` in shell scripts
- Add comprehensive error handling
- Include usage documentation

**YAML Configuration:**
- Use consistent indentation (2 spaces)
- Add comments explaining complex configurations
- Validate with `yamllint`

### Documentation

- Update README.md for new features
- Add inline comments for complex logic
- Create examples for new configurations
- Update CHANGELOG.md with changes

### Security Guidelines

This project handles sensitive infrastructure data. Follow these security practices:

**🔒 Environment Variables:**
- Never commit `.env` files or secrets
- Use environment variables for all sensitive data
- Copy from `env.example` and customize locally
- Keep SSH keys with 600 permissions

**📋 Pre-Contribution Security Checklist:**
```bash
# Run security audit before every commit
./common/scripts/security_audit.sh

# Verify no sensitive files are staged
git status --ignored

# Check for accidentally committed secrets
git log --oneline -p | grep -i "password\|secret\|key" || echo "Clean"
```

**🚨 If You Accidentally Commit Secrets:**
1. **DO NOT** just delete the file - it's still in git history
2. Contact security@brewnix.com immediately
3. Rotate any exposed credentials
4. Use `git-filter-branch` or BFG to clean history

### Testing

All contributions must include appropriate tests:

**Unit Tests:**
```bash
python -m pytest tests/ -v
```

**Integration Tests:**
```bash
cd docker-test-framework
./run-integration-tests.sh -t example -v
```

**Configuration Validation:**
```bash
./validate-config.sh
```

**Security Testing:**
```bash
# Run before every contribution
./common/scripts/security_audit.sh
```

## 🔄 Pull Request Process

### Before Submitting

1. **Run security audit** to ensure no sensitive data is committed:
   ```bash
   ./common/scripts/security_audit.sh
   ```
2. **Run all tests** and ensure they pass
3. **Update documentation** for any new features
4. **Add/update tests** for your changes
5. **Run linting tools**:
   ```bash
   ansible-lint ansible/
   terraform fmt -check terraform/
   yamllint config/
   ```

### Pull Request Guidelines

**Title Format:**
- `feat: add support for N305 CPU hardware`
- `fix: resolve VLAN configuration issue`
- `docs: update network setup guide`
- `test: add integration test for VPN setup`

**Description Must Include:**
- Summary of changes
- Issue number (if applicable): `Fixes #123`
- Type of change: `Bug fix | New feature | Breaking change | Documentation`
- Testing performed
- Screenshots (for UI changes)

**Review Process:**
1. Automated CI/CD checks must pass
2. Code review by maintainers
3. Integration testing (if needed)
4. Approval and merge

### Commit Guidelines

Use conventional commits format:
```
type(scope): description

[optional body]

[optional footer]
```

**Types:**
- `feat`: new feature
- `fix`: bug fix
- `docs`: documentation
- `style`: formatting changes
- `refactor`: code restructuring
- `test`: adding tests
- `chore`: maintenance tasks

**Examples:**
```
feat(hardware): add support for N305 CPU configuration

- Add N305 CPU template with proper core/thread settings
- Update hardware detection for Intel N-series
- Add validation for N305-specific features

Fixes #45

fix(networking): resolve VLAN tagging issue on OPNsense

The VLAN configuration was not applying correctly due to
interface naming mismatch. Updated the template to use
consistent interface names.

docs(setup): add troubleshooting section for network issues

Added common network configuration problems and solutions
based on user feedback in issues #67, #72, and #81.
```

## 🏷️ Project Structure

Understanding the project layout helps with contributions:

```
proxmox-firewall/
├── config/                 # Configuration templates and examples
│   ├── sites/             # Site-specific configurations
│   ├── devices/           # Device configuration templates
│   └── hardware/          # Hardware-specific settings
├── deployment/            # CI/Testing automation
│   ├── ansible/          # Testing playbooks
│   ├── scripts/          # Helper scripts
│   └── terraform/        # Testing infrastructure
├── proxmox-local/         # Production deployment
│   ├── ansible/          # Production playbooks
│   └── scripts/          # Production helper scripts
├── common/               # Shared components
│   ├── ansible/          # Common playbooks/roles
│   └── terraform/        # Reusable infrastructure modules
├── tests/                # Unit and validation tests
├── docker-test-framework/ # Integration testing environment
└── docs/                 # Project documentation
```

## 🐛 Debugging and Troubleshooting

### Common Development Issues

**Ansible Connection Issues:**
```bash
# Test connectivity
ansible-ping all -i inventory/

# Debug SSH issues
ansible-playbook -vvv playbook.yml
```

**Terraform State Issues:**
```bash
# Refresh state
terraform refresh

# Import existing resources
terraform import proxmox_vm_qemu.vm 100
```

**Configuration Validation Errors:**
```bash
# Detailed validation
./validate-config.sh -v

# Check specific component
yamllint config/sites/mysite.yml
```

### Getting Help

- **Discussions**: Use GitHub Discussions for questions
- **Issues**: Create issues for bugs and feature requests
- **Documentation**: Check docs/ directory and README
- **Examples**: Look at docker-test-framework/example-* configs
- **Direct Contact**: github@brewnix.com for repository-related inquiries

## 🏆 Recognition

Contributors are recognized in several ways:
- Listed in project contributors
- Mentioned in release notes for significant contributions
- Invited to maintainer team for sustained contributions

## 📄 License

By contributing to this project, you agree that your contributions will be licensed under the MIT License.

## 🤝 Code of Conduct

This project follows a contributor code of conduct:

- **Be respectful** of different viewpoints and experiences
- **Be inclusive** and welcoming to contributors of all backgrounds
- **Be constructive** in feedback and discussions
- **Focus on the project goals** and community benefit

Unacceptable behavior includes harassment, discrimination, or personal attacks. Report issues to the maintainers.

---

Thank you for contributing to the Proxmox Firewall project! 🎉 

> **Note for Integrators:**
> 
> This repository is designed to be included as a submodule in your own infrastructure project. All user-specific configuration and secrets should be kept in your parent repo, not in this codebase. See the [main README section on submodule usage](README.md#-using-as-a-submodule-recommended-for-integrators) and [docs/SUBMODULE_STRATEGY.md](docs/SUBMODULE_STRATEGY.md) for details. For new projects, start from the [proxmox-firewall-template](https://github.com/brewnix/proxmox-firewall-template) (coming soon).
