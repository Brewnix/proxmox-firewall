# Terraform (greenfield)

Provisions the **OPNsense** VM and **LXC** workloads on a Proxmox node. Pair with repo-root **`ansible/`** for host configuration.

## OPNsense install media

The OPNsense VM is created with an **empty** system disk until you run the installer from a **DVD ISO** on Proxmox.

1. **`./scripts/download_images.sh`** — fetches the official **dvd-amd64.iso**, checksum-verified, into **`images/`**, writes **`images/validated_images.json`**, and generates **`terraform/generated/opnsense_install.auto.tfvars`** (gitignored).
2. **`ansible-playbook ansible/playbooks/sync_images_to_proxmox.yml`** — copies that ISO to the node’s default ISO directory (`/var/lib/vz/template/iso`).
3. **`cd terraform && terraform apply -var-file=generated/opnsense_install.auto.tfvars`**

See **[docs/ISO_SOURCES.md](../docs/ISO_SOURCES.md)** for flags and legacy wrapper behavior.

## Files

- `main.tf` — VM/LXC resources, optional `cdrom` when `opnsense_install_iso_file_id` is set
- `variables.tf` — including `opnsense_install_iso_file_id`, `lxc_template_vmid`, `proxmox_node_name`
- `providers.tf` — `bpg/proxmox`
- `cloud-init/` — snippets for LXC services (OPNsense `opnsense.yml` is intentionally not cloud-init)

Firewall rule fragments for OPNsense live under **`OpnSenseXML/`** (see `OpnSenseXML/README.md`).
