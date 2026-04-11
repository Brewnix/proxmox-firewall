# OPNsense Terraform (browningluke/opnsense)

Declarative OPNsense objects that the provider supports (firewall aliases/rules/NAT, interfaces, routes, Kea DHCP, Unbound, VPN pieces, etc.). This stack is **separate** from [workloads/terraform](../terraform/) (`bpg/proxmox` guests) and from [proxmox/](../../proxmox/) (hypervisor).

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

[`firewall_aliases.tf`](firewall_aliases.tf) lines up with **[`OpnSenseXML/ALIASES.xml`](../../OpnSenseXML/ALIASES.xml)** (networks, hosts, ports). You can add VLANs, Unbound, Kea, and filter rules in this module as you adopt them; **gateway groups / gateway objects** are still mostly GUI-only in the provider (see [Drift and gaps](#drift-and-gaps)).

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

## Kea DHCP (import from UI)

If **Kea DHCPv4** is configured in the GUI, generate **`opnsense_kea_subnet`**, **`opnsense_kea_reservation`**, and **`opnsense_kea_peer`** blocks plus imports (uses `getSubnet` / `getReservation` / `getPeer` for accurate option data):

```bash
export OPNSENSE_URI="https://192.168.5.1"
export OPNSENSE_API_KEY="..."
export OPNSENSE_API_SECRET="..."

./scripts/generate_kea_imports.sh > generated_kea.tf.snippet
# Review, save as kea.tf (or split), terraform fmt, run each terraform import
# Order in output: subnets → reservations → peers
terraform plan
```

If `terraform plan` shows diffs on subnets (pools/options), compare the GUI to the generated HCL — OPNsense’s JSON shape can differ slightly by version.

**Import addresses:** Terraform resource names must **start with a letter or underscore**. Names like `192_168_1_0_24` are invalid; use the script output (it prefixes when needed, e.g. `kea_sn_192_168_1_0_24`) and keep the `resource` block label in `.tf` identical to the import line.

## Firewall rules (XML / UI vs Terraform)

For **now**, you can keep **authoritative** rules in **[`OpnSenseXML/`](../../OpnSenseXML/)** (or the GUI) and avoid managing the same rules in Terraform. When you are ready to move rules into Git, use **`opnsense_firewall_filter`** and patterns in [examples/firewall_filter.tf.example](examples/firewall_filter.tf.example) — rules reference aliases by **name** (e.g. `LAN_NET`). Do not edit the same rules in two places ([docs/GITOPS.md](../../docs/GITOPS.md)).

## Drift and gaps

- **Pre-v1 provider** — pin `version` in `versions.tf` and read upstream release notes.
- **Kea DHCP** — **`./scripts/generate_kea_imports.sh`** helps adopt existing Kea config; provider resources: **`opnsense_kea_subnet`**, **`opnsense_kea_reservation`**, **`opnsense_kea_peer`** ([docs](https://registry.terraform.io/providers/browningluke/opnsense/latest/docs)). Legacy **ISC DHCP** is not the same path.
- **Gateways / multi-WAN** — there is **no** gateway resource in this provider; static **`opnsense_route`** exists, but default gateway and gateway groups are still **GUI** (or API/scripts outside Terraform). Expect to keep that split or wait for upstream provider features.
- **Firewall rules** — **`opnsense_firewall_filter`** (and NAT resources) are supported; [`OpnSenseXML/`](../../OpnSenseXML/) remains a valid parallel if you prefer XML import — pick **one** authority per object class ([docs/GITOPS.md](../../docs/GITOPS.md)).
- Prefer **one** authority for overlapping objects (Git vs GUI vs XML).
