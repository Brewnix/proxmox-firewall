# OPNsense Terraform (browningluke/opnsense)

Declarative firewall objects that the provider supports (aliases, filter rules, VLANs where implemented). This stack is **separate** from [workloads/terraform](../terraform/) (`bpg/proxmox` guests) and from [proxmox/](../../proxmox/) (hypervisor).

## Prerequisites

- OPNsense installed and reachable at `opnsense_uri` (often VLAN 50).
- API key + secret: **System → Access → Users → [user] → API keys**.
- **HTTPS / TLS**: The provider defaults to **`opnsense_allow_insecure = true`** (same idea as `curl -k` and `./scripts/generate_alias_imports.sh`). Without it, URLs like `https://192.168.x.x` often fail with *certificate doesn’t contain any IP SANs* because the GUI cert is for a hostname, not the IP. Alternatives: use `opnsense_uri` with a **hostname** that matches the cert, install a proper CA on the box, or set `opnsense_allow_insecure = false` only when verification can succeed.
- **Apply order**: Proxmox host → workloads Terraform (guests) → OPNsense install/bootstrap → **this** directory.

## Quick start

```bash
cd workloads/terraform-opnsense
cp terraform.tfvars.example terraform.tfvars   # edit URI + API key/secret
terraform init
terraform plan
```

## Firewall aliases (import vs create)

[`firewall_aliases.tf`](firewall_aliases.tf) defines the same aliases as **[`OpnSenseXML/ALIASES.xml`](../../OpnSenseXML/ALIASES.xml)** (networks, hosts, ports). DNS/DHCP/gateways/VLANs stay on the firewall; only **aliases** are codified here until you add filter rules.

### If aliases **already exist** on the firewall

When `./scripts/generate_alias_imports.sh` prints **`terraform import`** lines (not only `# MISSING`), run those imports **only if** those resources are **not** already in Terraform state (e.g. you created them in the UI, or you are adopting an existing firewall). If you **just** ran `terraform apply` and it created the aliases, **do not** run the imports — state already matches; running imports would try to adopt the same UUIDs again and is unnecessary.

If **every** tracked alias is `# MISSING`, nothing matches yet — skip imports and use [If aliases do not exist yet](#if-aliases-do-not-exist-yet) instead.

Import UUIDs from the live API, then plan/apply for drift only:

```bash
export OPNSENSE_URI="https://192.168.5.1"    # your mgmt URL
export OPNSENSE_API_KEY="..."                 # public key part
export OPNSENSE_API_SECRET="..."              # secret

./scripts/generate_alias_imports.sh
# Run each printed line from this directory (imports one resource at a time)

terraform plan   # should show minimal or no changes if XML/UI matches .tf
```

Aliases on the firewall that **are not** in `firewall_aliases.tf` are listed as comments at the bottom of the script output (rename in TF or ignore).

### API 401 when running `generate_alias_imports.sh`

- Copy **`apikey.txt` exactly**: line 1 = key, line 2 = secret (include a **trailing `.`** on the secret if the file has one).
- **No** `key=` / `secret=` prefixes in the env vars — only the raw strings.
- A **truncated first character** on the key (e.g. missing leading `j`) causes 401 — paste from the file, not from memory.
- **System → Access → Settings**: ensure the API is enabled if your version exposes that toggle.
- Re-create the key if unsure; revoke the old one.

### If aliases **do not** exist yet

Skip imports; `terraform apply` will **create** them from `firewall_aliases.tf`.

## VLAN and Unbound (import from existing UI config)

If you already created **VLANs** and **Unbound** objects in the GUI, generate matching `.tf` snippets and `terraform import` lines from the live API:

```bash
export OPNSENSE_URI="https://192.168.5.1"
export OPNSENSE_API_KEY="..."
export OPNSENSE_API_SECRET="..."

./scripts/generate_unbound_vlan_imports.sh > generated_unbound_vlan.tf.snippet
# Review the file, split into e.g. interfaces_vlan.tf / unbound_dns.tf, adjust names if needed
terraform fmt
terraform import '...'   # run each printed import from workloads/terraform-opnsense
terraform plan           # expect no changes once state matches the firewall
```

The script covers **`opnsense_interfaces_vlan`**, **`opnsense_unbound_host_override`**, **`opnsense_unbound_forward`**, and **`opnsense_unbound_host_alias`**. It does **not** emit domain overrides (`opnsense_unbound_domain_override`) — add those by hand from the [provider docs](https://registry.terraform.io/providers/browningluke/opnsense/latest/docs) if your OPNsense version exposes them.

## Filter rules (next step)

Copy patterns from [examples/firewall_filter.tf.example](examples/firewall_filter.tf.example) into a new `.tf` file. Rules reference aliases by **name** (e.g. `LAN_NET`) — match [`OpnSenseXML/`](../../OpnSenseXML/) rule fragments when you add them.

## Drift and gaps

- **Pre-v1 provider** — pin `version` in `versions.tf` and read upstream release notes.
- **Gateways / multi-WAN / full DHCP** — often still GUI-first; Kea subnets/reservations are in the provider. **Unbound** — host overrides, forwards, aliases, and domain overrides are supported; not every GUI-only knob is mapped. See [docs/GITOPS.md](../../docs/GITOPS.md).
- Prefer **one** authority for overlapping objects (Git vs GUI).
