# GitOps layout

This repository uses **three separate Terraform state domains** (never mixed in one state file):

| Area | Directory | Provider(s) | When to apply |
|------|-----------|-------------|----------------|
| Proxmox host (optional TF) | [proxmox/terraform](../proxmox/terraform/) | `bpg/proxmox` (node-only, if used) | After OS install; before guests |
| Guests + snippets | [workloads/terraform](../workloads/terraform/) | `bpg/proxmox` | After host bridges/templates; Proxmox API up |
| OPNsense policy | [workloads/terraform-opnsense](../workloads/terraform-opnsense/) | `browningluke/opnsense` | After OPNsense install + API keys |

Ansible: [proxmox/ansible](../proxmox/ansible/) (host, golden LXC, ISO sync) then [workloads/ansible](../workloads/ansible/) (LXC snippet apply, future guest playbooks).

## CI and secrets

- Run `terraform plan` (and gated `apply`) **per directory** above.
- **Secrets**: Proxmox API token for `bpg` workloads; `OPNSENSE_*` or `terraform.tfvars` for OPNsense; never commit ([.gitignore](../.gitignore)).
- **Drift**: choose one authority for firewall rules — Terraform in `workloads/terraform-opnsense`, the **GUI** (including **CSV** import/export where the firewall UI offers it), or **[`OpnSenseXML/`](../OpnSenseXML/)** as reference / merge into a **full `config.xml`** — not a separate “import rules XML” wizard next to CSV. Full configuration **backup/restore** is **XML** under **System → Configuration → Backups** ([docs](https://docs.opnsense.org/manual/backups.html)). Kea DHCP can be imported via `workloads/terraform-opnsense/scripts/generate_kea_imports.sh` when moving DHCP into Terraform.

## Apply order

1. Proxmox host ([proxmox/ansible](../proxmox/ansible/)).
2. `cd workloads/terraform && terraform apply` (guests + snippets).
3. Install OPNsense from ISO if needed; create API keys.
4. `cd workloads/terraform-opnsense && terraform apply`.

See also [docs/LEGACY_MIGRATION.md](LEGACY_MIGRATION.md) for `deployment/` and `common/terraform`.
