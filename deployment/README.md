# Deployment Scripts

This directory contains the deployment scripts for setting up Proxmox firewall systems across multiple sites.

**Greenfield two-root layout** (preferred for new work): **[proxmox/](../proxmox/README.md)** (hypervisor Ansible) and **[workloads/](../workloads/README.md)** (guest Terraform + OPNsense API). See **[docs/LEGACY_MIGRATION.md](../docs/LEGACY_MIGRATION.md)** for how this relates to `deployment/` and `common/terraform`.

## Contents

- `ansible/`: Ansible playbooks for automated deployment and configuration
- `scripts/`: Helper scripts for site creation and deployment
- `terraform/`: Legacy infrastructure provisioning (called by Ansible); greenfield guests live under **`workloads/terraform/`**
- `config/`: External site configuration files (separate from automation)

## Architecture Overview

The deployment system uses a clean separation of concerns:

```
Site Config (External) → Ansible (Orchestration) → Terraform (Infrastructure)
     ↓                        ↓                        ↓
config/site.conf      group_vars/site.yml      TF_VAR_* environment
```

### Key Principles

1. **Single Source of Truth**: Site configuration lives in external `.conf` files
2. **No Generated Files**: Everything is dynamic, no `.tfvars` file generation
3. **Environment Variables**: Terraform receives all input via `TF_VAR_*` environment variables
4. **Separation of Concerns**: Site config, orchestration, and infrastructure are cleanly separated

## Multi-Site Deployment Process

### 1. Create Site Configuration

Use the site configuration script to create a new site:

```bash
./vendor/proxmox-firewall/deployment/scripts/create_site_config.sh
```

This creates:
- `config/<site_name>.conf` - External site configuration
- `ansible/group_vars/<site_name>.yml` - Minimal Ansible orchestration settings  
- Updates `.env` file with environment variables for Terraform

### 2. Deploy Infrastructure

Deploy the complete infrastructure using Ansible:

```bash
# Deploy all components for a site
ansible-playbook ansible/playbooks/05_deploy_vms.yml --limit=<site_name>

# Or use the master playbook for full deployment
ansible-playbook ansible/master_playbook.yml --limit=<site_name>
```

The deployment process:
1. Loads site configuration from external `config/<site_name>.conf` file
2. Sets up Terraform environment variables from site config
3. Provisions VMs using Terraform (OPNsense, Tailscale, Zeek, etc.)
4. Configures services and networking
5. Saves deployment state for tracking

## Configuration Files

### External Site Configuration (`config/<site_name>.conf`)

Contains all site-specific settings outside of the automation system:

```bash
# Site identification
SITE_NAME="primary"
SITE_DISPLAY_NAME="Primary Home"
NETWORK_PREFIX="10.1"
DOMAIN="primary.local"
PROXMOX_HOST="192.168.1.100"

# Hardware defaults
HARDWARE_CPU_TYPE="n100"
HARDWARE_CPU_CORES="4"
HARDWARE_MEMORY_TOTAL="8gb"

# Network interfaces
WAN_INTERFACE="eth0"
LAN_INTERFACE="eth2"
CAMERA_INTERFACE="eth3"
```

### Ansible Group Variables (`ansible/group_vars/<site_name>.yml`)

Contains minimal orchestration settings that reference the external config:

```yaml
site_config:
  name: "primary"
  display_name: "Primary Home"
  external_config_file: "{{ playbook_dir }}/../config/primary.conf"
  
  # Ansible-specific settings
  proxmox:
    api_secret_env: "PRIMARY_PROXMOX_API_SECRET"
  ssh:
    public_key_file: "{{ playbook_dir }}/../credentials/primary_root.pub"
```

### Environment Variables (`.env`)

Contains credentials and settings that Terraform reads via `TF_VAR_*` variables:

```bash
# Global settings
ANSIBLE_SSH_PRIVATE_KEY_FILE="~/.ssh/id_rsa"
PROXMOX_STORAGE_POOL="local-lvm"
TAILSCALE_AUTH_KEY="your_key_here"

# Site-specific credentials
PRIMARY_PROXMOX_API_SECRET="your_secret_here"
PRIMARY_NETWORK_PREFIX="10.1"
PRIMARY_DOMAIN="primary.local"
```

## Debugging and Maintenance

### Check Configuration
```bash
# View external site config
cat config/primary.conf

# Check Ansible variables
cat ansible/group_vars/primary.yml

# Verify environment variables
grep PRIMARY_ .env
```

### Deployment State
Deployment state is tracked in `deployment_state/<site_name>.state` for debugging and monitoring.

### Adding Devices
Use the device management script to add network devices to a site:

```bash
./vendor/proxmox-firewall/common/scripts/add_device.sh
```

This integrates with the site configuration system to manage DHCP reservations and firewall rules.
