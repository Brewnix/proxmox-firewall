# Legacy `deployment/` and `common/terraform` migration notes

The **current** greenfield layout is:

- **[proxmox/ansible/](../proxmox/ansible/)** — Proxmox VE host (repos, bridges, golden LXC template, ISO sync).
- **[workloads/terraform/](../workloads/terraform/)** — `bpg/proxmox` for OPNsense VM, service LXCs, and snippet uploads.
- **[workloads/terraform-opnsense/](../workloads/terraform-opnsense/)** — `browningluke/opnsense` for API-managed firewall objects.
- **[workloads/ansible/](../workloads/ansible/)** — Guest automation (e.g. LXC snippet apply).

Older paths still in the tree:

- **[deployment/ansible/](../deployment/ansible/)** — Multi-site playbooks, `telmate/proxmox`-era flows, master playbook. Migrate playbook-by-playbook into the two-root layout as needed; do not duplicate long-term maintenance in a third parallel stack.
- **[common/terraform/](../common/terraform/)** — `telmate/proxmox` modules (Tailscale, Netbird, Headscale, etc.). Prefer porting to **`bpg/proxmox`** under `workloads/terraform` when you touch a module.

When a legacy playbook is fully replaced, mark it deprecated in its header and link here.
