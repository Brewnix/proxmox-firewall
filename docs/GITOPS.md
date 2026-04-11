# GitOps layout

This repository uses **three separate Terraform state domains** (never mixed in one state file):

| Area | Directory | Provider(s) | When to apply |
|------|-----------|-------------|----------------|
| Proxmox host (optional TF) | [proxmox/terraform](../proxmox/terraform/) | `bpg/proxmox` (node-only, if used) | After OS install; before guests |
| Guests + snippets | [workloads/terraform](../workloads/terraform/) | `bpg/proxmox` | After host bridges/templates; Proxmox API up |
| OPNsense policy | [workloads/terraform-opnsense](../workloads/terraform-opnsense/) | `browningluke/opnsense` | After OPNsense install + API keys |

Ansible: [proxmox/ansible](../proxmox/ansible/) (host, golden LXC, ISO sync) then [workloads/ansible](../workloads/ansible/) (LXC cloud-init apply, future guest playbooks).

## CI and secrets

- Run `terraform plan` (and gated `apply`) **per directory** above.
- **Secrets**: Proxmox API token for `bpg` workloads; `OPNSENSE_*` or `terraform.tfvars` for OPNsense; never commit ([.gitignore](../.gitignore)).
- **Drift**: choose one authority for firewall rules — Terraform in `workloads/terraform-opnsense`, or [OpnSenseXML/](../OpnSenseXML/) / XML import — and avoid editing the same objects in the GUI without importing.

## Apply order

1. Proxmox host ([proxmox/ansible](../proxmox/ansible/)).
2. `cd workloads/terraform && terraform apply` (guests + snippets).
3. Install OPNsense from ISO if needed; create API keys.
4. `cd workloads/terraform-opnsense && terraform apply`.

See also [docs/LEGACY_MIGRATION.md](LEGACY_MIGRATION.md) for `deployment/` and `common/terraform`.
