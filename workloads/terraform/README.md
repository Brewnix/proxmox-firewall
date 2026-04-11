# Terraform (greenfield guests)

Provisions the **OPNsense** VM and **LXC** workloads on a Proxmox node. Pair with **[proxmox/ansible/](../../proxmox/ansible/)** for host configuration and **[workloads/ansible/](../ansible/)** to apply LXC snippets after apply.

## OPNsense install media

The OPNsense VM is created with an **empty** system disk until you run the installer from a **DVD ISO** on Proxmox.

1. **`./scripts/download_images.sh`** — downloads **`OPNsense-*-dvd-amd64.iso.bz2`** from **pkg.opnsense.org**, verifies **`OPNsense-*-checksums-amd64.sha256`**, runs **`bunzip2`**, leaves **`images/OPNsense-*-dvd-amd64.iso`**, writes **`images/validated_images.json`**, and **`workloads/terraform/generated/opnsense_install.auto.tfvars`** (gitignored).
2. **`ansible-playbook proxmox/ansible/playbooks/sync_images_to_proxmox.yml`** — copies that ISO to the node’s default ISO directory (`/var/lib/vz/template/iso`).
3. **`cd workloads/terraform && terraform apply`** — if `opnsense_install_iso_file_id` is empty, the VM module reads **`../../images/validated_images.json`** from **`scripts/download_images.sh`**. You can still pass **`-var-file=generated/opnsense_install.auto.tfvars`** to mirror that file.

The installer CD is on **`ide2`** (Proxmox default). While both disk and ISO are present, **`boot_order` is `virtio0` then `ide2`**: the VM tries the system disk first and only falls through to the ISO when the disk has no bootloader (fresh install). After OPNsense is on disk, set **`opnsense_install_iso_file_id = ""`** and apply so boot is **`virtio0`** only.

See **[docs/ISO_SOURCES.md](../docs/ISO_SOURCES.md)** for flags and legacy wrapper behavior.

## Files

- `main.tf` — VM/LXC resources, optional `cdrom` when `opnsense_install_iso_file_id` is set
- `variables.tf` — including `opnsense_install_iso_file_id`, `lxc_template_vmid`, `proxmox_node_name`
- `providers.tf` — `bpg/proxmox`
- `cloud-init/*.yaml.tftpl` — **Terraform `templatefile()`** renders these and uploads them as Proxmox **snippets** (real values for `ssh_public_key`, `tailscale_auth_key`, etc.). Plain `.yml` without templating is not used.

### Cloud-init: OPNsense vs Linux guests

- **OPNsense (VM 200):** Proxmox may list a **cloud-init–style** drive or `initialization` metadata (leftover or provider defaults). **OPNsense still is not a Linux cloud image** — install and configure from the **ISO / serial installer**; do not expect `#cloud-config` to run inside the guest. Terraform uses `lifecycle.ignore_changes` on `initialization` so you can delete a stray seed volume in the UI without endless diffs.
- **Linux LXCs (201–203):** Snippets are **uploaded** (`pihole.yaml`, `tailscale.yaml`, `omada.yaml`) but **not attached** by Terraform — see **LXC user-data** below. (Linux **QEMU** templates in **`deployment/ansible/roles/vm_templates/tasks/ubuntu_cloud.yml`** use **`qm set … --cicustom`** and **`ide2 … cloudinit`** — that is **VM-only**.)

### LXC user-data (why `pct set --cicustom` can fail)

- **`qm set <vmid> --cicustom "user=local:snippets/…"`** is for **QEMU VMs** and is widely supported.
- **`pct set … --cicustom`** exists only on **newer Proxmox VE** builds that ship **cloud-init integration for containers**. On many nodes **`pct`** prints **`Unknown option: cicustom`** — that is expected; your version simply has no such flag.
- **Works everywhere (Debian/Ubuntu CT with `cloud-init` installed):** copy the rendered snippet into the guest **NoCloud** seed path, then reboot or run cloud-init:

  ```bash
  # Snippet path for storage "local" is usually:
  SNIP=/var/lib/vz/snippets/pihole.yaml   # or tailscale.yaml / omada.yaml

  # Required: the CT must have the cloud-init package (minimal Debian templates often do not).
  pct exec 201 -- bash -lc 'apt-get update && apt-get install -y cloud-init'

  pct exec 201 -- mkdir -p /var/lib/cloud/seed/nocloud
  pct push 201 "$SNIP" /var/lib/cloud/seed/nocloud/user-data
  pct exec 201 -- bash -lc 'cloud-init clean --logs'
  pct exec 201 -- bash -lc 'cloud-init init --local'
  pct exec 201 -- bash -lc 'cloud-init modules --mode=config'
  pct exec 201 -- bash -lc 'cloud-init modules --mode=final'
  # or: pct reboot 201
  ```

  If you see **`Failed to exec "cloud-init"`**, install **`cloud-init`** in the CT first (line above), or bake it into your **golden LXC template** so clones already have it.

  Use VMID **201** / **202** / **203** and the matching filename. If **`pct push`** fails, stop the CT once (`pct stop 201`) and retry.

### LXC vs QEMU for Linux (cloud-init reality)

Proxmox **QEMU** guests get first-class **cloud-init**: **`qm set --cicustom`**, **`ide2` cloud-init drive**, and Terraform **`user_data_file_id`** on **`proxmox_virtual_environment_vm`**. That matches **`deployment/ansible/roles/vm_templates/tasks/ubuntu_cloud.yml`** (Ubuntu cloud image + cloud-init storage).

**LXC** has no portable equivalent on older **`pct`** builds, so common patterns are:

1. **Push + script** — e.g. **`pct push` `vmid` `/path/provision.sh` `/usr/local/bin/provision.sh`** then **`pct exec`** (see [this forum thread](https://forum.proxmox.com/threads/q-how-best-to-work-with-cloud-init-and-lxc.119126/)); often followed by **Ansible** for the rest.
2. **NoCloud seed** — the **`pct push`** snippet into **`/var/lib/cloud/seed/nocloud/user-data`** flow above (fragile if the template lacks **`cloud-init`** or datasources differ).
3. **Run the workload as a small QEMU VM** — trade RAM/disk for **`cicustom`** and the same **`#cloud-config`** workflow as public clouds.

This greenfield stack uses **LXCs** for light services (Pi-hole, Tailscale, Omada). If you want **everything** driven by cloud-init from Terraform with no host-side glue, prefer **QEMU templates** for those roles or keep **one** wrapper script on the Proxmox node that maps VMID → snippet.

### LXC cloud-init and Tailscale

The **`bpg/proxmox`** `proxmox_virtual_environment_container` resource does **not** attach `user_data` the way QEMU VMs do. Uploaded snippets must be applied on the node (see above).

1. **`terraform apply`** refreshes **`local:snippets/pihole.yaml`**, **`tailscale.yaml`**, **`omada.yaml`** with interpolated values.
2. Set **`tailscale_auth_key`** (and **`ssh_public_key`**) in **`terraform.tfvars`** (gitignored). Optional: **`tailscale_advertise_routes`** (default `192.168.0.0/16`).
3. Inject user-data with **`pct push`** + **`cloud-init`** (or **`pct set --cicustom`** only if your **`pct set --help`** lists it). Recreate or reboot the CT so the first-boot path runs if needed.

**Automated apply (Ansible)** — from the repo root:

`ansible-playbook workloads/ansible/playbooks/lxc-apply-cloud-init-snippets.yml`

The Tailscale CT also gets **`TS_AUTHKEY`** in **`environment_variables`** when `tailscale_auth_key` is non-empty (useful for `pct exec` / debugging). **`terraform output lxc_cloud_init_snippet_ids`** shows the stored file ids.

### Pi-hole LXC checklist (VMID **201**)

Unattended install **requires** `/etc/pihole/setupVars.conf` **before** `bash … --unattended` — the rendered **`pihole.yaml`** snippet does that (plus **`PIHOLE_SKIP_OS_CHECK`**, **`systemd-resolved`** off, **`features.nesting`** on the CT).

1. **`terraform apply`** — optional: **`pihole_lxc_ipv4`** (must be **CIDR**, e.g. **`192.168.5.2/24`** — bare `192.168.5.2` makes Proxmox return **400 invalid ipv4 network configuration**), **`pihole_lxc_gateway`**, **`pihole_admin_password`** in **`terraform.tfvars`** (password defaults to a placeholder if unset).
2. **Apply** user-data to the CT (**not** `qm set`): use **`pct push`** to **`/var/lib/cloud/seed/nocloud/user-data`** as in the section above, or **`pct set 201 --cicustom …`** only if your Proxmox version supports it (`pct set --help`). Then **reboot** or run **`cloud-init`** inside the guest.
3. **OPNsense:** allow **UDP/TCP 53** from internal VLANs → **192.168.5.2**; point **Kea/Dnsmasq** DNS to Pi-hole when ready.
4. If install still fails (e.g. **Pi-hole v6** behavior changes), run the [interactive installer](https://docs.pi-hole.net/main/basic-install/) once inside the CT and compare **`/etc/pihole/setupVars.conf`** to upstream docs.

You can keep **DHCP DNS = OPNsense (Unbound)** until Pi-hole is healthy, then switch DHCP DNS to **192.168.5.2**.

### Firewall aliases / rules (when L3 is done)

With VLANs, gateways, DHCP, and DNS working, follow **`OpnSenseXML/README.md`**: **aliases** from **`ALIASES.xml`**, then rules in the listed order (**WAN** → **MAIN** → **MGMT** → **IOT** → **CAM** → **GUEST** → **CLUSTER**). Pi-hole can be layered in anytime by updating the **PiHole_DNS** alias and DHCP DNS.

Firewall rule fragments for OPNsense live under **`OpnSenseXML/`** (see `OpnSenseXML/README.md`).

## Golden LXC template + redeploying Terraform CTs

1. **Build the template** (Debian 12 + `cloud-init` + `ansible` + `ansible` user; Proxmox host gets `ansible` too):

   ```bash
   cd proxmox/ansible
   ansible-playbook -i inventory/hosts.yaml playbooks/lxc-golden-template.yml --limit pve-firewall
   ```

   Rebuild from scratch (destructive for VMID **9001**):  
   `-e lxc_golden_force_rebuild=true`

   If **DHCP** is not available on **`vmbr2`**, set e.g.  
   `-e 'lxc_golden_net0=name=eth0,bridge=vmbr2,ip=192.168.x.x/24,gw=192.168.x.1'`.

2. **Match Terraform** — ensure **`lxc_template_vmid`** in **`terraform.tfvars`** equals **`lxc_golden_vmid`** (default **9001**).

3. **Redeploy Linux CTs** so clones use the new template — destroy then recreate (example targets):

   ```bash
   cd workloads/terraform
   terraform destroy -target=proxmox_virtual_environment_container.pihole \
     -target=proxmox_virtual_environment_container.tailscale \
     -target=proxmox_virtual_environment_container.omada
   terraform apply
   ```

   Or remove CTs **201–203** in the Proxmox UI, then **`terraform apply`**. Terraform-managed LXCs **clone** the golden template; replacing the template alone does **not** change existing CTs until they are recreated.
