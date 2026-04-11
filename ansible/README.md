# Moved: use `proxmox/ansible/`

Host playbooks now live under **[proxmox/ansible/](../proxmox/ansible/)** (inventory, `proxmox-host-base.yml`, `lxc-golden-template.yml`, `sync_images_to_proxmox.yml`).

```bash
cd proxmox/ansible
ansible-playbook -i inventory/hosts.yaml playbooks/proxmox-host-base.yml --limit pve-firewall
```
