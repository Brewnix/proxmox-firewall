# README

## Layout

```text
ansible/
├── ansible.cfg
├── inventory/
│   ├── hosts.yml
│   └── group_vars/
│       ├── all.yml
│       ├── tennessee.yml
│       └── primary_home.yml
├── playbooks/
│   ├── 01_initial_setup.yml
│   ├── 02_terraform_api.yml
│   ├── 03_network_setup.yml
│   ├── 04_vm_templates.yml
│   └── 05_deploy_vms.yml
└── roles/
    ├── proxmox_base/
    ├── proxmox_network/
    ├── proxmox_api/
    ├── vm_templates/
    ├── deploy_opnsense/
    ├── deploy_omada/
    └── deploy_tailscale/
../../common/scripts/fetch_credentials.sh
```

### VM Software Configuration

The `vm_software` section in your site configuration allows you to specify custom update scripts for VMs that require special handling beyond standard system updates. This is used by the VM version management playbook to keep your VMs up to date.

Example configuration:

```yaml
vm_software:
  omada:
    update_script: /usr/local/bin/update_omada.sh
    notify_on_update: true
  netbird:
    update_script: /usr/local/bin/update_netbird.sh
    notify_on_update: true
```

The playbook will:

1. Run standard system updates for all VMs
2. Execute custom update scripts for VMs that have them configured
3. Create snapshots before updates
4. Roll back to snapshots if updates fail
5. Send notifications when updates are available (if configured)

Note: Most VMs will handle their own package updates through standard system updates. Only specify custom update scripts for VMs that need special handling (e.g., Home Assistant, Zeek, Pangolin) or have their own update mechanisms.
