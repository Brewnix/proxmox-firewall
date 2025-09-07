<div align="center">

# 🔥 Proxmox Firewall

**Enterprise-grade firewall infrastructure with automated deployment**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![CI Status](https://img.shields.io/badge/CI-Passing-brightgreen.svg)](#testing--validation)
[![Ansible](https://img.shields.io/badge/Ansible-2.9+-red.svg)](https://www.ansible.com/)
[![Terraform](https://img.shields.io/badge/Terraform-1.0+-blue.svg)](https://www.terraform.io/)
[![Python](https://img.shields.io/badge/Python-3.8+-blue.svg)](https://www.python.org/)

**[Documentation](#-documentation) • [Quick Start](#-quick-start) • [Architecture](#-architecture) • [Features](#-features)**

</div>

---

## 🚀 Quick Start (Modern GitOps Deployment)

> **Proxmox Firewall now uses modern GitOps deployment with USB bootstrapping and continuous drift detection, replacing the legacy proxmox-local approach.**

### Prerequisites

- Ubuntu 20.04+ or similar Linux distribution
- 8GB+ RAM, 50GB+ storage for development
- Git repository for GitOps configuration management
- Tailscale authentication key for VPN setup

### 1. GitOps Deployment (Recommended)

```bash
# Deploy with GitOps repository
./vendor/proxmox-firewall/gitops/deploy-gitops.sh \
  --operation deploy \
  --gitops-repo https://github.com/yourorg/firewall-config.git \
  config/sites/your-site/firewall-site.yml

# Enable continuous drift detection
sudo systemctl enable brewnix-drift-detection.timer
sudo systemctl start brewnix-drift-detection.timer
```

### 2. USB Bootstrap Deployment (Zero-Touch)

```bash
# Create USB bootstrap image
./vendor/proxmox-firewall/gitops/deploy-gitops.sh \
  --operation usb-create \
  --usb-device /dev/sdb \
  config/sites/your-site/firewall-site.yml

# Insert USB into Proxmox server and run:
# /media/usb/bootstrap.sh
```

### 3. Traditional Deployment (Legacy Support)

```bash
# Use the vendor deployment system
../../scripts/deploy-vendor.sh proxmox-firewall config/sites/your-site/firewall-site.yml
```

### 4. Configure Your Project

- Place your site configuration, secrets, and inventory in the `config/` directory of your parent repo (if not already created by the script).
- Edit `.env` with your environment variables and credentials.
- Add or update additional submodules (e.g., NAS, K8s, VPN) as needed.

> **Note:** This order ensures all scripts and configuration files exist before you edit or customize them, reducing errors and confusion for new users.

### 5. Deploy Infrastructure

- **Install the custom Proxmox ISO** you created earlier on your hardware:
  - Write the ISO to a USB drive and boot your server from it
  - Complete the Proxmox installation process

> **See [docs/PROXMOX_ANSWER_FILE.md](docs/PROXMOX_ANSWER_FILE.md) for details on the answer file format, fields, and customization.**

- **After Proxmox is installed and online, deploy your site configuration with Ansible:**

  **Testing/CI Environment:**

  ```bash
  ansible-playbook vendor/proxmox-firewall/deployment/ansible/master_playbook.yml --limit=<site_name>
  ```

  **Production Environment:**
  
  ```bash
  cd vendor/proxmox-firewall/proxmox-local/ansible
  ansible-playbook site.yml --limit=<site_name>
  ```

---

## 🧩 Submodule Workflow & Best Practices

- **All your config and secrets stay in your repo** (never in the submodule)
- **Update submodules** for new features/fixes as needed
- **Run scripts from the submodule, passing your config**
- See [docs/SUBMODULE_STRATEGY.md](docs/SUBMODULE_STRATEGY.md) for advanced usage

---

## 📖 Detailed Installation Guide (Submodule Workflow)

> **All steps below assume you are using the template repo and proxmox-firewall as a submodule in `vendor/proxmox-firewall/`.**

### 0. Environment Variables

```bash
cp env.example .env
```

Edit the `.env` file in your parent repo to set variables for the custom proxmox iso and variables for ansible.

### 1. Install Prerequisites

```bash
./vendor/proxmox-firewall/deployment/scripts/prerequisites.sh
```

### 2. Download Latest Images

```bash
./vendor/proxmox-firewall/deployment/scripts/download_latest_images.sh
```

### 3. Configure Sites

```bash
./vendor/proxmox-firewall/deployment/scripts/create_site_config.sh
```

This script will:

- Ask for site details (name, network prefix, domain, Proxmox host)
- Create external site configuration files (`config/<site_name>.conf`)
- Create minimal Ansible orchestration settings (`ansible/group_vars/<site_name>.yml`)
- Update `.env` file with environment variables for Terraform
- No `.tfvars` files are generated - everything uses environment variables

### 4. Configure Devices

```bash
./vendor/proxmox-firewall/deployment/scripts/add_device.sh
```

This script will:

- Help you select device templates
- Configure device settings
- Set up DHCP reservations
- Update firewall rules
- **Create or update device configuration files in `config/devices/<site_name>/` as needed**

**Alternatively, you can manually add device entries directly to your site YAML file (`config/sites/<site_name>.yml`).** This is useful for advanced users, bulk editing, or when you want full control over the device configuration format.

- See [README_DEVICES.md](README_DEVICES.md) for detailed device format, examples, and advanced options for both script-based and manual editing.

> **Tip:** Use the script for ease and guided setup, or edit the YAML directly for advanced scenarios or automation.

### 5. Customize Site and Device Configurations

- Edit site configurations in `config/sites/<site_name>.yml`
- Modify device configurations in `config/devices/<site_name>/`
- Update `.env` file with credentials and MAC addresses

```bash
# Validate your configuration before deployment
./vendor/proxmox-firewall/validate-config.sh <site_name>
```

### 6. Create Custom Proxmox ISO

```bash
ansible-playbook vendor/proxmox-firewall/deployment/ansible/playbooks/create_proxmox_iso.yml
```

This playbook will:

- Generate a custom Proxmox ISO with site/firewall specific answer files
- Optionally include hardware-specific configurations

### 7. Deploy Proxmox

```bash
sudo dd if=proxmox-custom.iso of=/dev/sdX bs=4M status=progress conv=fsync

# Install Proxmox on your hardware
# - Boot from USB
# - Installation will proceed automatically
# - Server will reboot when complete
```

### 8. Fetch Credentials

The `common/scripts/fetch_credentials.sh` script is used to retrieve and store credentials after deployment:

```bash
# Fetch credentials for a specific site (run after Proxmox deployment)
./vendor/proxmox-firewall/common/scripts/fetch_credentials.sh <site_name>
```

This will:

- Retrieve API tokens and keys from deployed systems
- Store them securely in the credentials directory
- Update the .env file with the retrieved values

### 9. Deploy Infrastructure and Configuration

**For CI/Testing and Initial Validation:**

```bash
# Validate configuration and run tests
./vendor/proxmox-firewall/validate-config.sh <site_name>

# Deploy basic infrastructure for testing
ansible-playbook vendor/proxmox-firewall/deployment/ansible/master_playbook.yml --limit=<site_name>
```

**For Production Deployment (run remotely first time):**

```bash
# Complete production deployment with OPNsense configuration
cd vendor/proxmox-firewall/proxmox-local/ansible
ansible-playbook site.yml --limit=<site_name>

# Or for maintenance (can be run locally on Proxmox server)
ansible-playbook site.yml --tags maintenance
```

The production deployment process:

- Loads site configuration from `config/sites/<site_name>.yml`
- Validates required environment variables from site config
- Provisions VMs using Terraform (OPNsense, Tailscale, Zeek, etc.)
- Configures OPNsense firewall with site-specific rules
- Sets up Tailscale VPN integration
- Deploys Suricata IDS/IPS and Zeek monitoring
- Configures automated backups and maintenance
- Provides comprehensive deployment status report

---

## ⚙️ Configuration Architecture

This site yaml shows a **inline single-file approach** for devices (add_device.sh is recommended see [README_DEVICES](README_DEVICES.md)):

### Site Configuration Example (`config/sites/<site_name>.yml`)

```yaml
site:
  name: "primary"
  display_name: "Primary Home"
  network_prefix: "10.1"
  domain: "primary.local"
  
  hardware:
    network:
      vlans:
        - id: 10
          name: "main"
          subnet: "10.1.10.0/24"
        - id: 20
          name: "cameras"
          subnet: "10.1.20.0/24"
  
  proxmox:
    host: "192.168.1.100"
    node_name: "pve"
    
  vm_templates:
    opnsense:
      enabled: true
      cores: 4
      memory: 4096
    tailscale:
      enabled: true
    zeek:
      enabled: true
      
  security:
    firewall:
      default_policy: "deny"
    suricata:
      enabled: true
      
  backup:
    enabled: true
    schedule: "0 2 * * *"
    retention: 7
      
  credentials:
    proxmox_api_secret: "PRIMARY_PROXMOX_API_SECRET"
    tailscale_auth_key: "TAILSCALE_AUTH_KEY"

devices:
  nas:
    ip_address: "10.1.10.100"
    vlan_id: 10
  camera_nvr:
    ip_address: "10.1.20.2"
    vlan_id: 20
```

### Environment Variables (`.env`)

```bash
# Global settings
TAILSCALE_AUTH_KEY="your_tailscale_auth_key"

# Site-specific credentials
PRIMARY_PROXMOX_API_SECRET="your_proxmox_api_secret"
```

### 🔒 Security Audit

Before deploying or contributing, run the security audit script to ensure no sensitive data is accidentally committed:

```bash
./common/scripts/security_audit.sh
```

This script checks for:

- Comprehensive `.gitignore` patterns
- Accidentally committed sensitive files  
- Proper environment variable configuration
- SSH key permissions
- Hardcoded secrets in configuration files

### 🏠 Local Management (Post-Deployment)

After initial deployment, set up automated local management on your Proxmox server:

```bash
# Run on Proxmox server to enable automatic updates from your fork
./common/scripts/setup_local_management.sh https://github.com/YOUR_USERNAME/proxmox-firewall.git primary
```

This enables:

- **🔄 Automatic updates** from your GitHub fork (every 15 minutes)
- **🏗️ Local Terraform state** management
- **📋 Continuous monitoring** and status reporting
- **🔒 Secure operation** with all secrets remaining local

See [Local Management Documentation](docs/LOCAL_MANAGEMENT.md) for details.

## 🔧 Key Benefits

- **🏗️ Infrastructure as Code**: Complete automation with Ansible and Terraform
- **🔒 Security First**: Multi-layered security with comprehensive monitoring
- **📱 Modern Management**: Web-based dashboards and API access
- **⚡ Performance**: Optimized for high-throughput networking
- **🛡️ Reliability**: Automated backups, health checks, and failover
- **📊 Visibility**: Comprehensive logging and network analysis
- **🌐 Scalability**: Easy multi-site deployment and management

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for detailed information on:

- Development environment setup
- Code style guidelines  
- Pull request process
- Documentation standards
- Testing requirements

Quick contribution steps:

1. Fork the repository (for code contributions only)
2. Create a feature branch
3. Run tests: `./validate-config.sh`
4. Submit a pull request to the main repo

---

## 🕰️ Legacy: Manual Forking (Single-Site/Quick Start)

> **This section is for users who want a quick, single-site deployment and do not plan to scale or integrate with other infrastructure.**

### Manual Forking Steps

1. **Fork this repository** to your GitHub account (click "Fork" button above)

2. **Clone your fork**:

   ```bash
   git clone https://github.com/YOUR-USERNAME/proxmox-firewall.git
   cd proxmox-firewall
   ```

3. **Run the setup script** to customize all URLs for your fork:

   ```bash
   ./scripts/setup-fork.sh YOUR-USERNAME
   ```

4. **Continue with the rest of the setup as described above, but note that this approach is not recommended for multi-site, multi-component, or GitOps workflows.**

> **For detailed development and testing installation instructions (not for production), see [docs/DEVELOPMENT_INSTALL.md](docs/DEVELOPMENT_INSTALL.md).**

## 🚀 Overview

A comprehensive [Proxmox](https://pve.proxmox.com/wiki/Installation)-based firewall solution featuring **OPNsense**, **Tailscale VPN**, **Omada Controller**, and **Suricata IDS/IPS**. Designed for multi-site deployments with automated provisioning, advanced security monitoring, and enterprise-grade networking capabilities.

### 🎯 Key Features

- **🔐 Multi-layered Security**: OPNsense firewall + Suricata IDS/IPS + Zeek network monitoring
- **🌐 Multi-site VPN**: Tailscale mesh networking with subnet routing
- **⚡ Automated Deployment**: Complete infrastructure-as-code with Ansible & Terraform
- **📊 Advanced Monitoring**: Network traffic analysis, threat detection, and security dashboards
- **🔄 WAN Failover**: Automatic failover between fiber and satellite connections
- **🏠 Device Management**: Automated DHCP, VLAN isolation, and firewall rules
- **💾 Backup & Recovery**: Automated backups with configurable retention
- **🔧 Configuration Management**: Single YAML file per site with comprehensive validation

## 📋 Hardware Recommendations

| Component | Specification | Notes |
|-----------|---------------|-------|
| **CPU** | N100 to N355 | Low power, high efficiency |
| **Memory** | 8GB-32GB | 16GB+ recommended for monitoring |
| **Storage** | 128-512GB SSD | + CEPH or NAS for backups |
| **Network** | 3-8x I226v 2.5GbE | Multiple interfaces for VLANs |
| **Uplink** | 1-2x SFP+ 10GbE | Optional, ideal for high throughput |

## 📚 Documentation

| Document | Description |
|----------|-------------|
| **[📚 Complete Documentation](docs/README.md)** | Full documentation index and guides |
| **[🚀 Quick Start Guide](#-quick-start)** | Get up and running in minutes |
| **[🔧 Deployment Guide](deployment/README.md)** | Complete deployment automation |
| **[⚙️ Site Configuration](proxmox-local/ansible/SITE_CONFIG.md)** | Site-specific configuration management |
| **[🌐 Multi-site Setup](README_MULTISITE.md)** | Managing multiple locations |
| **[🏠 Device Management](README_DEVICES.md)** | Network device configuration |
| **[📡 Network Configuration](config/NETWORK_PREFIX_FORMAT.md)** | VLAN and network design |
| **[🔐 Security Policy](SECURITY.md)** | Security practices and vulnerability reporting |
| **[🛠️ Troubleshooting](docs/TROUBLESHOOTING.md)** | Common issues and solutions |
| **[🔌 API Documentation](docs/API.md)** | API reference for automation |
| **[🧪 Testing Framework](tests/README.md)** | Automated testing and validation |
| **[🐳 Docker Test Environment](docker-test-framework/QUICK_START.md)** | Local development and testing |
| **[🤝 Contributing Guide](CONTRIBUTING.md)** | How to contribute to the project |
| **[📋 Changelog](CHANGELOG.md)** | Release notes and changes |
| **[📝 TODO](TODO.md)** | Planned features and improvements |

## 🧪 Testing & Validation

The project includes comprehensive testing to ensure reliability:

- **✅ Configuration Validation**: Automated YAML syntax and structure validation
- **✅ Integration Tests**: End-to-end deployment testing with mock services
- **✅ Security Tests**: Firewall rules, VPN connectivity, and IDS/IPS validation
- **✅ Network Tests**: VLAN isolation, connectivity, and routing verification
- **✅ Service Health**: Automated monitoring of all deployed services

```bash
# Run comprehensive validation
./validate-config.sh

# Run integration tests
cd docker-test-framework && docker-compose up --build test
```

## 🏗️ Architecture

```mermaid
graph TB
    A[Site Configuration<br/>config/sites/site.yml] --> B[Ansible Orchestration]
    B --> C[Terraform Infrastructure]
    B --> D[OPNsense Configuration]
    B --> E[Security Services]
    
    C --> F[Proxmox VMs]
    D --> G[Firewall Rules]
    D --> H[VPN Integration] 
    E --> I[Suricata IDS/IPS]
    E --> J[Zeek Monitoring]
    
    F --> K[Production Environment]
    G --> K
    H --> K
    I --> K
    J --> K
```

### Configuration Flow

```text
Single YAML File → Ansible (Direct Read) → Terraform (Environment Variables)
       ↓                    ↓                        ↓
config/sites/site.yml   Direct Processing      TF_VAR_* environment
```

## 🚀 Fork based deployment (only for development or testing)

### 1. Fork and Clone Your Repository

```bash
# First: Fork this repository on GitHub to YOUR-USERNAME/proxmox-firewall
# Then clone YOUR fork (not the original):
git clone https://github.com/YOUR-USERNAME/proxmox-firewall.git
cd proxmox-firewall

# Set up your fork with correct URLs:
./scripts/setup-fork.sh YOUR-USERNAME

# Configure environment:
cp env.example .env
# Edit .env with your configuration
```

### 2. Install Dependencies

```bash
./deployment/scripts/prerequisites.sh
```

### 3. Create Site Configuration

```bash
./deployment/scripts/create_site_config.sh
./validate-config.sh <site_name>
```

### 4. Deploy (Choose One)

**Testing/CI Environment:**

```bash
ansible-playbook deployment/ansible/master_playbook.yml --limit=<site_name>
```

**Production Environment:**

```bash
cd proxmox-local/ansible
ansible-playbook site.yml --limit=<site_name>
```

## 🧩 Using as a Submodule (Recommended for Integrators)

> **This repository is designed to be included as a submodule in your own infrastructure project.**

For most users, forking this repo is sufficient. For advanced users or integrators managing multiple sites or custom infrastructure, we recommend using this repo as a submodule in your own project, keeping all your configuration and secrets in your parent repo.

### Official Project Template

- See the [proxmox-firewall-template](https://github.com/Brewnix/proxmox-firewall-template) (coming soon) for a ready-to-fork project structure with this repo as a submodule and example config.

### Recommended Structure

```text
my-firewall-project/
├── config/                # Your site-specific configuration, secrets, inventory, etc.
├── vendor/
│   └── proxmox-firewall/  # This repo as a submodule
├── .env                   # Your environment variables
└── ...
```

### Workflow

- **All your config and secrets stay in your repo**
- **This repo provides all code, scripts, and automation**
- **Update the submodule for new features/fixes**
- **Run scripts from the submodule, passing your config**

### Script Compatibility

- All scripts/tools support both local config and parent-repo config when used as a submodule.
- See [docs/SUBMODULE_STRATEGY.md](docs/SUBMODULE_STRATEGY.md) for discussion on submodule GitOps and best practices.

> **For detailed instructions on managing and deploying multiple sites, see [README_MULTISITE.md](README_MULTISITE.md).**

## 🖼️ Sample Network Diagrams

Below are example network diagrams to help you visualize a typical multi-VLAN Proxmox Firewall deployment and device layout. You can adapt these to your own site and device plan.

### 1. Site-Level Network Diagram

```mermaid
flowchart TD
    subgraph Site_Network["Site: Example Home Network"]
        WAN["WAN (ISP)"]
        FW["OPNsense Firewall<br/>vmbr0 (WAN)"]
        SW["Switch"]
        LAN["LAN VLAN 10<br/>vmbr1.10"]
        CAM["Cameras VLAN 20<br/>vmbr1.20"]
        IOT["IoT VLAN 30<br/>vmbr1.30"]
        GUEST["Guest VLAN 40<br/>vmbr1.40"]
        MGMT["Mgmt VLAN 50<br/>vmbr1.50"]
        NAS["NAS<br/>10.1.10.10"]
        PC["Desktop PC<br/>10.1.10.20"]
        CAM1["Camera 1<br/>10.1.20.10"]
        IOT1["IoT Device 1<br/>10.1.30.10"]
        GUEST1["Guest Device<br/>10.1.40.10"]
        MGMT1["Proxmox Host Mgmt<br/>10.1.50.1"]
    end
    WAN --> FW
    FW --> SW
    SW --> LAN
    SW --> CAM
    SW --> IOT
    SW --> GUEST
    SW --> MGMT
    LAN --> NAS
    LAN --> PC
    CAM --> CAM1
    IOT --> IOT1
    GUEST --> GUEST1
    MGMT --> MGMT1
    style FW fill:#e0eaff,stroke:#0366d6,stroke-width:2px
    style SW fill:#fffbe6,stroke:#ffd33d
    style LAN fill:#eaffea,stroke:#28a745
    style CAM fill:#ffeaea,stroke:#d63333
    style IOT fill:#eafffa,stroke:#33d6b3
    style GUEST fill:#f0eaff,stroke:#7d33d6
    style MGMT fill:#eaf0ff,stroke:#3366d6
```

### 2. VLAN/Device Mapping Diagram

```mermaid
flowchart TD
    subgraph VLANs["VLANs and Devices"]
        LAN["VLAN 10: LAN<br/>10.1.10.0/24"]
        CAM["VLAN 20: Cameras<br/>10.1.20.0/24"]
        IOT["VLAN 30: IoT<br/>10.1.30.0/24"]
        GUEST["VLAN 40: Guest<br/>10.1.40.0/24"]
        MGMT["VLAN 50: Mgmt<br/>10.1.50.0/24"]
        NAS["NAS<br/>10.1.10.10"]
        PC["Desktop PC<br/>10.1.10.20"]
        CAM1["Camera 1<br/>10.1.20.10"]
        IOT1["IoT Device 1<br/>10.1.30.10"]
        GUEST1["Guest Device<br/>10.1.40.10"]
        MGMT1["Proxmox Host Mgmt<br/>10.1.50.1"]
    end
    LAN --> NAS
    LAN --> PC
    CAM --> CAM1
    IOT --> IOT1
    GUEST --> GUEST1
    style LAN fill:#eaffea,stroke:#28a745
    style CAM fill:#ffeaea,stroke:#d63333
    style IOT fill:#eafffa,stroke:#33d6b3
    style GUEST fill:#f0eaff,stroke:#7d33d6
    style MGMT fill:#eaf0ff,stroke:#3366d6
```

---

## 🔄 GitOps Migration Guide

> **The Proxmox Firewall project has been modernized with GitOps deployment, replacing the legacy proxmox-local approach. This section documents the migration path and new features.**

### What Changed

#### Legacy Approach (proxmox-local)
- Manual configuration copying to `/opt/proxmox-firewall/`
- Static deployment scripts run locally on Proxmox
- Manual drift detection and configuration management
- Limited automation and error-prone updates

#### Modern Approach (GitOps)
- **Configuration as Code**: All configurations stored in Git repositories
- **Automated Drift Detection**: Continuous monitoring with 5-minute intervals
- **USB Bootstrap**: Zero-touch deployment via USB devices  
- **Webhook Notifications**: Real-time alerts for configuration changes
- **Automatic Sync**: GitOps repository changes trigger automatic updates

### Migration Steps

#### 1. Backup Existing Configuration
```bash
# Backup legacy proxmox-local configuration
cp -r vendor/proxmox-firewall/proxmox-local-legacy/ backup/
```

#### 2. Setup GitOps Repository
```bash
# Create or use existing GitOps repository
git clone https://github.com/yourorg/firewall-config.git
cd firewall-config

# Initialize configuration structure
mkdir -p config/sites/your-site
cp backup/proxmox-local-legacy/config/site.yml config/sites/your-site/firewall-site.yml
```

#### 3. Deploy with GitOps
```bash
# Modern deployment with drift detection
./vendor/proxmox-firewall/gitops/deploy-gitops.sh \
  --operation deploy \
  --gitops-repo https://github.com/yourorg/firewall-config.git \
  config/sites/your-site/firewall-site.yml
```

#### 4. Enable Continuous Monitoring
```bash
# Start drift detection service
sudo systemctl enable brewnix-drift-detection.timer
sudo systemctl start brewnix-drift-detection.timer

# Check service status
systemctl status brewnix-drift-detection.timer
```

### New GitOps Features

#### Drift Detection
- **Continuous Monitoring**: Checks every 5 minutes for configuration changes
- **GitOps Sync**: Automatically detects and applies repository updates
- **System Validation**: Monitors VM state, firewall rules, and service health
- **Alert Integration**: Slack/webhook notifications for drift events

#### USB Bootstrap
- **Zero-Touch Deployment**: Create bootable USB with embedded configuration
- **Automated Setup**: Complete infrastructure deployment from USB device
- **SSH Key Injection**: Automatic SSH access configuration
- **Network Bootstrap**: Automatic network configuration and Git cloning

#### GitOps Operations
```bash
# Check for configuration drift
./gitops/deploy-gitops.sh --operation drift-check site-config.yml

# Sync from GitOps repository  
./gitops/deploy-gitops.sh --operation sync site-config.yml

# Create USB bootstrap image
./gitops/deploy-gitops.sh --operation usb-create --usb-device /dev/sdb site-config.yml

# Backup current configuration
./gitops/deploy-gitops.sh --operation backup site-config.yml
```

### Configuration Management

#### Environment Variables
```bash
# Required for GitOps deployment
export TAILSCALE_AUTH_KEY="your-tailscale-key"
export GRAFANA_ADMIN_PASSWORD="secure-password"

# Optional for advanced features
export GITOPS_WEBHOOK_URL="https://hooks.slack.com/..."
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export BACKUP_S3_BUCKET="firewall-backups"
```

#### Drift Detection Configuration
```bash
# Configure drift detection intervals
export DRIFT_CHECK_INTERVAL=300  # 5 minutes

# Configure GitOps repository
export GITOPS_REPO="https://github.com/yourorg/firewall-config.git"

# Configure site configuration
export SITE_CONFIG="/path/to/firewall-site.yml"
```

### Legacy Support

The legacy `proxmox-local` approach is still supported but deprecated:

```bash
# Legacy deployment (deprecated)
cd vendor/proxmox-firewall/proxmox-local-legacy/ansible
ansible-playbook -i inventory/hosts.yml site.yml
```

### Benefits of GitOps Approach

- **🔄 Automated Updates**: GitOps repository changes trigger automatic deployment
- **📊 Drift Detection**: Continuous monitoring prevents configuration drift  
- **🔧 Zero-Touch Deploy**: USB bootstrap eliminates manual setup
- **📱 Real-Time Alerts**: Webhook notifications for all configuration changes
- **📦 Version Control**: Full audit trail of all infrastructure changes
- **🛡️ Security**: Immutable infrastructure with automated rollback
- **⚡ Fast Recovery**: USB bootstrap enables rapid disaster recovery

### Troubleshooting

#### Drift Detection Issues
```bash
# Check drift detection service
journalctl -u brewnix-drift-detection -f

# Manual drift check
./gitops/drift-detector.sh --check-once --site-config site.yml

# View drift state
cat /var/lib/brewnix/drift-state.json
```

#### GitOps Sync Problems
```bash
# Manual GitOps sync
./gitops/deploy-gitops.sh --operation sync --verbose site.yml

# Check GitOps repository status
git -C /tmp/gitops-repo status
```

---

**Proxmox Firewall with GitOps: Enterprise-grade security infrastructure with modern automation! 🔥**
