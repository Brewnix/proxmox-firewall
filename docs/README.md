# Documentation Index

Welcome to the Proxmox Firewall project documentation! This directory contains comprehensive guides and references for all aspects of the project.

## 📚 Documentation Overview

### 🚀 Getting Started
- **[Main README](../README.md)** - Project overview and quick start
- **[Contributing Guide](../CONTRIBUTING.md)** - How to contribute to the project
- **[Security Policy](../SECURITY.md)** - Security practices and vulnerability reporting

### Setup and installation
- **[Development install](DEVELOPMENT_INSTALL.md)** — toolchain and local setup
- **[Network prefix / VLAN mapping](../config/NETWORK_PREFIX_FORMAT.md)** — address plan conventions
- **[Proxmox answer file (host ISO)](PROXMOX_ANSWER_FILE.md)** — automated PVE install

### Deployment
- **[GitOps layout](GITOPS.md)** — Terraform state per root, apply order, secrets
- **[Legacy migration](LEGACY_MIGRATION.md)** — `deployment/` and `common/terraform` vs `proxmox/` + `workloads/`
- **[Deployment Guide](../deployment/README.md)** — older Ansible-orchestrated multi-site flow
- **[ISO / image sources](ISO_SOURCES.md)** — `scripts/download_images.sh`, sync playbook, generated tfvars

### Configuration
- **[Network configuration](../config/NETWORK_PREFIX_FORMAT.md)** — VLAN and network design
- **[Multi-site setup](../README_MULTISITE.md)** — multiple locations
- **[Device management](../README_DEVICES.md)** — DHCP and device templates
- **[OPNsense XML fragments](../OpnSenseXML/README.md)** — aliases and rule ordering (import or reference)
- **[OPNsense Terraform](../workloads/terraform-opnsense/README.md)** — API-managed rules (browningluke provider)
- **[OPNsense web UI (first login)](OPNSENSE_WEB_UI.md)** — HTTPS GUI, listen interfaces, SSH

### Security
- **[Security policy](../SECURITY.md)** — reporting and practices
- **[Troubleshooting](TROUBLESHOOTING.md)** — common issues

### 🧪 Testing
- **[Testing Guide](../tests/README.md)** - Automated testing and validation
- **[Docker Test Environment](../docker-test-framework/QUICK_START.md)** - Local development and testing
- **[Troubleshooting](TROUBLESHOOTING.md)** - Common issues and solutions

### 🏠 Management
- **[Local Management](LOCAL_MANAGEMENT.md)** - Automated Proxmox self-management system
- **[Submodule Integration](SUBMODULE_STRATEGY.md)** – How to use this repo as a submodule in your own project
- **[Main README](../README.md)** — project overview (submodule consumers: see [SUBMODULE_STRATEGY](SUBMODULE_STRATEGY.md))

### Integration
- **[API documentation](API.md)** — automation notes

### Reference
- **[Changelog](../CHANGELOG.md)** — release notes
- **[TODO](../TODO.md)** — planned work
- **[FAQ](reference/FAQ.md)** — frequently asked questions

## Documentation structure

```
docs/
├── README.md            # This index
├── GITOPS.md            # Terraform roots, state, CI
├── LEGACY_MIGRATION.md  # deployment/ + common/terraform
├── ISO_SOURCES.md
├── API.md
├── TROUBLESHOOTING.md
└── reference/
    └── FAQ.md
```

## 📖 Documentation Guidelines

### Writing Documentation

When contributing documentation:

1. **Use clear headings** with emoji for visual organization
2. **Include code examples** with proper syntax highlighting
3. **Add troubleshooting sections** for common issues
4. **Keep examples up-to-date** with current configuration formats
5. **Cross-reference related documents** with relative links

### Documentation Standards

- **Markdown format** for all documentation files
- **Consistent emoji usage** for section headers
- **Code blocks** with language specification
- **Relative links** for internal references
- **Examples** should be complete and runnable

## 🆘 Need Help?

If you can't find what you're looking for:

1. **Search the documentation** using your browser's find function
2. **Check the troubleshooting guide** for common issues
3. **Review the FAQ** for frequently asked questions
4. **Create a GitHub issue** if you found a documentation gap
5. **Join GitHub Discussions** for community help

## 🤝 Contributing to Documentation

Documentation improvements are always welcome! See our [Contributing Guide](../CONTRIBUTING.md) for:

- How to submit documentation updates
- Writing style guidelines
- Review process for documentation changes
- Tips for creating clear, helpful guides

---

**Last Updated**: 2025-01-12  
**Version**: 1.0.0 
