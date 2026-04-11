# Proxmox firewall (BrewNix)

Automation for **Proxmox VE** on compact hardware (for example Intel **N305** class systems) with **OPNsense**, **WAN diversity**, and **VLAN isolation** (main, IoT, cameras, guest, management, cluster). Infrastructure is split into two roots: **hypervisor** vs **workloads**, each with its own Terraform state when you adopt remote backends.

## Quick layout

| Root | Path | Purpose |
|------|------|---------|
| **Proxmox host** | [proxmox/ansible/](proxmox/ansible/) | Host repos, bridges, golden LXC template, ISO sync to the node. Optional node-only Terraform: [proxmox/terraform/](proxmox/terraform/). |
| **Workloads** | [workloads/](workloads/) | Guests on Proxmox (`bpg/proxmox`), OPNsense API (`browningluke/opnsense`), and guest Ansible (e.g. LXC cloud-init apply). |

Typical order: prepare the **Proxmox** host → **`terraform apply`** in [workloads/terraform/](workloads/terraform/) → install **OPNsense** from ISO → **`terraform apply`** in [workloads/terraform-opnsense/](workloads/terraform-opnsense/) when API keys exist.

## Documentation

- **[workloads/terraform/README.md](workloads/terraform/README.md)** — OPNsense VM, LXCs, cloud-init snippets.
- **[docs/GITOPS.md](docs/GITOPS.md)** — state separation, CI, secrets, drift.
- **[docs/LEGACY_MIGRATION.md](docs/LEGACY_MIGRATION.md)** — `deployment/` and `common/terraform` vs the new layout.
- **[OpnSenseXML/README.md](OpnSenseXML/README.md)** — firewall aliases and rule ordering.
- **[docs/README.md](docs/README.md)** — full documentation index.

## Submodule / template note

Some paths still reference the historical **submodule-core** template scripts (`dev-setup.sh`, `local-test.sh`). Greenfield operations use **`proxmox/`** and **`workloads/`** above.
