# Proxmox Local Scripts

This directory contains the scripts and configurations that will be deployed to /opt/proxmox-firewall/ on the Proxmox server.

## Contents

- ansible/: Operational Ansible playbooks and roles for production deployment
- terraform/: Local Terraform configurations and state
- scripts/: Maintenance and scheduling scripts
- config/: Site and device configurations

## Production Deployment

### First Time Remote Deployment

Run the master playbook remotely from your deployment console:

```bash
cd proxmox-local/ansible
ansible-playbook -i inventory/hosts.yml site.yml --limit <site_name>
```

This will:
1. Set up basic Proxmox infrastructure
2. Deploy and configure VMs
3. Configure OPNsense firewall with site-specific rules
4. Set up Tailscale VPN integration
5. Deploy Suricata IDS/IPS monitoring
6. Configure Zeek network analysis
7. Set up automated backups and monitoring
8. Provide a comprehensive deployment summary

### Local Maintenance

After initial deployment, you can rerun playbooks locally on the Proxmox server:

```bash
cd /opt/proxmox-firewall/ansible
ansible-playbook site.yml --tags maintenance
```

### Individual Components

Run specific parts of the deployment:

```bash
# Just OPNsense configuration
ansible-playbook site.yml --tags security

# Just backup configuration  
ansible-playbook site.yml --tags backup

# Just monitoring setup
ansible-playbook site.yml --tags monitoring
```

## Environment Variables

Ensure these are set before running:
- `PROXMOX_API_SECRET`
- `TAILSCALE_AUTH_KEY`
- `OPNSENSE_API_KEY`
- `OPNSENSE_API_SECRET`

## Setup

1. Copy this directory to /opt/proxmox-firewall/
2. Configure .env file with site and device IDs
3. Run the site.yml playbook for complete deployment
