# OPNsense Terraform (browningluke/opnsense)

Declarative firewall and L3 objects that the provider supports (aliases, filter rules, VLANs, etc.). This stack is **separate** from [workloads/terraform](../terraform/) (`bpg/proxmox` guests) and from [proxmox/](../../proxmox/) (hypervisor).

## Prerequisites

- OPNsense installed and reachable at `opnsense_uri` (often VLAN 50).
- API key + secret on the firewall.
- **Apply order**: Proxmox host → workloads Terraform (guests) → OPNsense install/bootstrap → **this** directory.

## Usage

```bash
cd workloads/terraform-opnsense
cp terraform.tfvars.example terraform.tfvars   # edit
terraform init
terraform plan
```

Add resources in `main.tf` or copy from [examples/firewall_filter.tf.example](examples/firewall_filter.tf.example).

## Drift and gaps

- **Pre-v1 provider** — pin `version` in `versions.tf` and read upstream release notes.
- **Gateways / multi-WAN failover** — not fully represented in the provider; use [OpnSenseXML](../../OpnSenseXML/), Ansible, or `config.xml` flows ([forum thread](https://forum.opnsense.org/index.php?topic=42517.0)).
- Prefer **one** source of truth for rules (Git vs GUI) — see [docs/GITOPS.md](../../docs/GITOPS.md).
