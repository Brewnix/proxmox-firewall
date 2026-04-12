# Workloads automation (shared)

Terraform and Ansible for **guests** (OPNsense VM, LXCs, future VMs) and **OPNsense API** policy. Reusable across sites via workspaces or per-site `*.tfvars`.

## Contents

| Path | Role |
|------|------|
| [terraform/](terraform/) | `bpg/proxmox`: OPNsense QEMU VM, Pi-hole / Tailscale / Omada LXCs; **snippets** (`#cloud-config` YAML) on `local:snippets`. |
| [terraform-opnsense/](terraform-opnsense/) | `browningluke/opnsense`: aliases, filter rules, VLANs (per provider coverage). |
| [ansible/](ansible/) | Post-apply guest tasks — e.g. [playbooks/lxc-apply-cloud-init-snippets.yml](ansible/playbooks/lxc-apply-cloud-init-snippets.yml) (attach snippets / NoCloud). |

**Pair with** [proxmox/ansible/](../proxmox/ansible/) for the hypervisor (bridges, golden template, ISO sync).

## QEMU vs LXC (strategy)

| Pattern | Use when |
|---------|----------|
| **LXC** | Light services (Pi-hole, Tailscale, Omada): lower RAM/disk; snippets + Ansible apply ([terraform/README.md](terraform/README.md)). |
| **QEMU + cloud-init** | You want **`user_data_file_id`** / cloud-image semantics on the VM resource (e.g. Ubuntu cloud images: [deployment/ansible/roles/vm_templates/tasks/ubuntu_cloud.yml](../deployment/ansible/roles/vm_templates/tasks/ubuntu_cloud.yml)) instead of post-apply LXC snippet wiring. Trade higher overhead per guest. |

**OPNsense** stays **QEMU** (not a Linux cloud image); configure via ISO installer then [terraform-opnsense/](terraform-opnsense/) or XML/Ansible for gaps.
