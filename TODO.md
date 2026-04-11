# TODO / backlog

*Last reviewed: 2026-04-10* — bump this date whenever you refresh priorities or complete a planning pass.

Use this file when **scoping later-stage plans** (milestones, PR batches, or design docs). It is **not** a substitute for issues—promote items to GitHub when work is funded or scheduled.

**Pointers:** greenfield layout **[`proxmox/`](proxmox/)** (hypervisor) + **[`workloads/`](workloads/)** (guests, OPNsense API). GitOps and state split: **[`docs/GITOPS.md`](docs/GITOPS.md)**. Legacy migration: **[`docs/LEGACY_MIGRATION.md`](docs/LEGACY_MIGRATION.md)**.

---

## Near term — validate and stabilize

- Exercise **greenfield** path on target hardware (resource limits, real NICs).
- **Proxmox addressing:** DHCP for first boot, then **static** on planned management net — implemented; needs **field testing**.
- Bring **automated tests** closer to a live stack (parity with production assumptions).

## Consolidation — legacy stacks

- **Migrate** [`proxmox-local-legacy/`](proxmox-local-legacy/) and [`common/terraform/`](common/terraform/) / [`deployment/ansible/`](deployment/ansible/) into the **two-root** model (or deprecate with documented parity). See [`docs/LEGACY_MIGRATION.md`](docs/LEGACY_MIGRATION.md).
- **Extract a BrewNix core** — reusable Terraform/Ansible slice — once the firewall repo is stable enough to submodule or publish.

## OPNsense and L3 policy

- **Provider gaps:** multi-WAN / gateway groups / failover — still mostly **Ansible**, XML, or GUI until [`browningluke/opnsense`](https://registry.terraform.io/providers/browningluke/opnsense) (or wrappers) cover them.
- **Single source of truth:** reconcile **[`OpnSenseXML/`](OpnSenseXML/)** with **[`workloads/terraform-opnsense/`](workloads/terraform-opnsense/)** (import, generate, or pick one authority).
- **LXC post-apply (optional polish):** idempotent snippet apply (e.g. hash compare), inventory from Terraform outputs instead of fixed VMIDs — see [`workloads/ansible/playbooks/lxc-apply-cloud-init-snippets.yml`](workloads/ansible/playbooks/lxc-apply-cloud-init-snippets.yml).
- **Ubuntu / QEMU guests** in [`workloads/terraform/`](workloads/terraform/) when something needs full `user_data` / `cicustom` without LXC glue — pattern in [`deployment/ansible/roles/vm_templates/tasks/ubuntu_cloud.yml`](deployment/ansible/roles/vm_templates/tasks/ubuntu_cloud.yml).

## GitOps and delivery

- **Remote state and secrets** — formalize backends, env, vault; extend beyond examples in `backend.tf.example` files.
- **CI/CD:** gated `terraform plan`/`apply` per root; optional GitHub Actions deploy workflows.
- **USB / bootstrap** — offline or air-gapped first boot toward Git connectivity.
- **Template repo / submodule** story for downstream integrators (align with [`docs/SUBMODULE_STRATEGY.md`](docs/SUBMODULE_STRATEGY.md)).

## Observability

- **Prometheus**, **snmp_exporter**, **Grafana** on or behind the firewall lab.
- **Zabbix** (SNMP) VM or container if desired.
- Evaluate **bsnmp** on OPNsense vs exporters-only.

## Multi-site and global connectivity

- **Per-site topologies** (not one-size VLAN map).
- **Examples:** Tailscale / Headscale / Netbird — Terraform + Ansible patterns; global config TBD.
- **Self-hosted VPN control plane** — DMZ VM, cloud VM, DNS split — design doc before implementation.

## Operations and maintenance

- **Non-apt workloads:** update scripts for curl-style installers that do not ship apt sources.
- **Backup health** — dashboard or checks for VM backup success.
- **Hardware validation** — audit [`proxmox-local-legacy/`](proxmox-local-legacy/) / deployment hardware playbooks vs real N305-class boxes.

## Proxmox host automation

- **Answer file (TOML):** Jinja validation and fixes for [`docs/PROXMOX_ANSWER_FILE.md`](docs/PROXMOX_ANSWER_FILE.md) pipeline — [PVE automated install](https://pve.proxmox.com/wiki/Automated_Installation).

## Documentation and accuracy

- **Mermaid (or similar) diagrams:** VLANs, example devices, traffic paths.
- **Audit docs:** [`docs/API.md`](docs/API.md) examples, [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) commands, [`docs/reference/FAQ.md`](docs/reference/FAQ.md) vs current behavior.

## Security stack validation (when IDS/monitoring is deployed)

- Zeek logging, Suricata rules, log rotation, alert paths — verify end-to-end.

## Workloads not on this box (policy only)

- **NAS / k3s** and similar — usually [`README_DEVICES.md`](README_DEVICES.md) + OPNsense rules unless the workload runs **on** this Proxmox; then add to [`workloads/terraform/`](workloads/terraform/) deliberately.
