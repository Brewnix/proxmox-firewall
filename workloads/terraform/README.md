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
- `scripts/attach_lxc_cloud_init_snippets.sh` — optional **on-node** helper: **NoCloud** seed + **`cloud-init`** inside each CT (same behavior as the Ansible playbook).

### Required after `terraform apply` (LXCs 201–203)

**`terraform apply` uploads rendered `#cloud-config` YAML to Proxmox as snippets** (`local:snippets/pihole.yaml`, `tailscale.yaml`, `omada.yaml`). The **`bpg/proxmox`** provider does **not** attach those files to **`proxmox_virtual_environment_container`** the way it can pass **`user_data_file_id`** on QEMU VMs. Until you apply a snippet on the node or inside the guest, **nothing from those files runs** (no Pi-hole install, no Tailscale join, etc.).

**Do one of:**

1. **Ansible (recommended)** — from repo root (uses **[`ansible.cfg`](../../ansible.cfg)** → **`proxmox/ansible/inventory/hosts.yaml`**):  
   `ansible-playbook workloads/ansible/playbooks/lxc-apply-cloud-init-snippets.yml`  
   If Ansible still reports **no hosts matched**, pass **`-i proxmox/ansible/inventory/hosts.yaml`** or edit **`proxmox/ansible/inventory/hosts.yaml`** so **`ansible_host`** reaches your node (e.g. **`fw`**).
2. **On the Proxmox node as root** — [`scripts/attach_lxc_cloud_init_snippets.sh`](scripts/attach_lxc_cloud_init_snippets.sh) (**`pct push`** to **`/var/lib/cloud/seed/nocloud/`** + **`pct exec … cloud-init …`**). No reboot required if **`cloud-init modules --mode=final`** completes; check **`/var/log/cloud-init-output.log`** in the CT if not.

### Management VLAN on `vmbr3` (Pi-hole / Tailscale / Omada)

If the Proxmox host uses a **VLAN subinterface** for mgmt (e.g. **`vmbr3.50`** with **192.168.5.1**), the **LXC NIC must use the same 802.1Q tag** (`vlan_id = 50`). Otherwise the CT stays on the trunk’s **native VLAN**, gets no path to **192.168.5.1**, and pings from the host show **Destination Host Unreachable**. Terraform sets **`management_vlan_id`** (default **50**) on those LXCs — align it with your bridge. Flat **untagged** mgmt on `vmbr3` only: remove **`vlan_id`** from **`network_interface`** in **`main.tf`** or fork the pattern.

### DNS inside service LXCs (201–203)

**Important — Proxmox vs CT vs OPNsense:** The **Proxmox host** can use your **ISP router** (`192.168.0.1`) for internet. **LXCs do not share the host’s routing.** In this Terraform stack, each LXC gets a **static IP and default gateway** from **`main.tf`** (by default **`192.168.5.x/24`**, gateway **`192.168.5.1`** = OPNsense on **VLAN 50**). **Every packet** from the CT to the internet — including DNS to **`1.1.1.1`** — goes **via that default gateway**. Changing only **`/etc/resolv.conf`** (Ansible **`lxc_resolv_nameservers`**) does **not** move the CT onto the “Proxmox LAN”; it only changes which resolver IP **`apt`** queries. If OPNsense **blocks or redirects** DNS, or has no working WAN, **resolution fails** even with **`1.1.1.1`** in **`resolv.conf`**.

**`lxc_dns_servers`** (default **`["192.168.5.1"]`**) sets **`initialization.dns`** on each CT. Point at whatever answers DNS **from that CT’s subnet** (usually **OPNsense Unbound** on **`192.168.5.1`** for this design), not Pi-hole, until Pi-hole is running.

#### Flat LAN bootstrap (ISP router = gateway; no OPNsense in the CT path)

To put service LXCs on the **same /24 as the home router** (e.g. **`192.168.0.0/24`**) so the default gateway is **`192.168.0.1`** (not OPNsense), set in **`terraform.tfvars`** (adjust host IPs to avoid DHCP clashes; align **`lxc_bridge`** and **`management_vlan_id`** with physical layout — **wrong bridge** gives **`Destination Host Unreachable`** to the gateway even when IP/VLAN look correct):

```hcl
# Same bridge as the Proxmox host’s 192.168.0.x NIC (often vmbr2 = main LAN). vmbr3 is the Omada trunk in this repo.
lxc_bridge            = "vmbr2"
# Untagged — must match how the switch/router uses VLANs (0 = no 802.1Q tag on this NIC).
management_vlan_id    = 0
# Many home routers do not answer DNS on 192.168.0.1:53 — use a public resolver first for bootstrap, then Pi-hole.
lxc_dns_servers       = ["1.1.1.1", "192.168.0.1"]
pihole_lxc_ipv4       = "192.168.0.201/24"
pihole_lxc_gateway    = "192.168.0.1"
tailscale_lxc_ipv4    = "192.168.0.202/24"
tailscale_lxc_gateway = "192.168.0.1"
omada_lxc_ipv4        = "192.168.0.203/24"
omada_lxc_gateway     = "192.168.0.1"
```

Then **`terraform apply`**, fix **`vlan_id`** / bridge if needed, and align **Ansible** **`lxc_resolv_nameservers`** in **`proxmox/ansible/inventory/host_vars/`** with the same list as **`lxc_dns_servers`**.

**When `nameserver` is the LAN gateway but resolution still fails**, the problem is on **OPNsense** (or path to it), not “stupid” generic firewall blame: **Unbound** may not be listening on the right interface; **rules** may block **UDP/TCP 53** from the mgmt subnet to the firewall; **port redirects** may send all DNS to Pi-hole while Pi-hole is not installed yet; **WAN/NAT** for the VLAN may be broken (HTTPS from the CT will fail too). **ICMP to the internet** (e.g. ping `1.1.1.1`) is often **blocked on WAN** while TCP is allowed — ping loss alone does not prove outage.

If you use **public resolvers** in **`resolv.conf`** (`1.1.1.1`, etc.), your **LAN firewall rules** must allow **UDP/TCP 53** to those addresses from the mgmt network, or queries will time out.

Terraform can report **no changes** while the **guest** still has an empty or stale **`resolv.conf`**. The Ansible playbook **`lxc-apply-cloud-init-snippets.yml`** can overwrite **`/etc/resolv.conf`** from **`lxc_resolv_nameservers`** before DNS checks — override with **`-e`** if your resolvers differ.

### Staged build (LAN-only, WAN not finished yet)

If **OPNsense is only connected temporarily** (e.g. **DHCP on LAN**) while you validate the layout, **WAN may not be up** and **Unbound will not resolve public names** — so **nothing on the mgmt VLAN** (including Pi-hole CTs with **`nameserver 192.168.5.1`**) can resolve **`deb.debian.org`**. **ping / nslookup toward the internet** failing in that phase is **normal** until the firewall has a working upstream path and DNS forwarding.

The **Pi-hole `runcmd`** path (**`curl install.pi-hole.net`**, **`apt`**) **needs internet**. Options: bring **WAN + DNS** online first, then run **`lxc-apply-cloud-init-snippets.yml`**; or use **`-e lxc_skip_dns_preflight=true`**, **`-e lxc_skip_cloud_init_install=true`**, and **`-e lxc_skip_cloud_init_final=true`** so **`cloud-init`** runs only through **`config`** (users, **`write_files`**) and **not** **`final` / `runcmd`**, then **re-run without those skips** when the network is ready. **`lxc_skip_cloud_init_install`** is only valid if the **`cloud-init`** package is **already** in each CT (otherwise omit it so **`apt`** can install **`cloud-init`**).

### Cloud-init: OPNsense vs Linux guests

- **OPNsense (VM 200):** Proxmox may list a **cloud-init–style** drive or `initialization` metadata (leftover or provider defaults). **OPNsense still is not a Linux cloud image** — install and configure from the **ISO / serial installer**; do not expect `#cloud-config` to run inside the guest. Terraform uses `lifecycle.ignore_changes` on `initialization` so you can delete a stray seed volume in the UI without endless diffs.
- **Linux LXCs (201–203):** Snippets are **uploaded** (`pihole.yaml`, `tailscale.yaml`, `omada.yaml`) but **not attached** by Terraform — see **Snippets and the Linux guest** below. (Linux **QEMU** templates in **`deployment/ansible/roles/vm_templates/tasks/ubuntu_cloud.yml`** use **`qm set … --cicustom`** and **`ide2 … cloudinit`** — that is **VM-only**.)

### Snippets, `pct`, and the Linux guest (`cloud-init`)

- **`qm set <vmid> --cicustom "user=local:snippets/…"`** is the usual path for **QEMU VMs** (and matches **`user_data_file_id`** on **`proxmox_virtual_environment_vm`** in this provider).
- **LXCs** are **not** Linux cloud-image appliances: Proxmox **stores** your rendered YAML as **snippets**; wiring that into the container is **separate** from `terraform apply`. This repo’s Ansible playbook and **`attach_lxc_cloud_init_snippets.sh`** **seed NoCloud inside the guest** and **run `cloud-init` there**—do not assume **`pct set --cicustom`** alone will run your **`#cloud-config`** on an LXC the way a QEMU cloud image does.
- **NoCloud (Debian/Ubuntu CT with `cloud-init` installed):** copy the rendered snippet into the guest **NoCloud** seed path, then reboot or run cloud-init:

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

### LXC vs QEMU: different provisioning models

**QEMU** cloud templates match the usual **cloud-init** story: **`qm set --cicustom`**, **`ide2` cloud-init drive**, and Terraform **`user_data_file_id`** on **`proxmox_virtual_environment_vm`**. That matches **`deployment/ansible/roles/vm_templates/tasks/ubuntu_cloud.yml`** (Ubuntu cloud image + cloud-init storage).

**LXCs** in **`bpg/proxmox`** do not get an automatic **`user_data_file_id`**—this stack **uploads snippets** only. Common patterns are:

1. **Push + script** — e.g. **`pct push` `vmid` `/path/provision.sh` `/usr/local/bin/provision.sh`** then **`pct exec`** (see [this forum thread](https://forum.proxmox.com/threads/q-how-best-to-work-with-cloud-init-and-lxc.119126/)); often followed by **Ansible** for the rest.
2. **NoCloud seed** — the **`pct push`** snippet into **`/var/lib/cloud/seed/nocloud/user-data`** flow above (needs **`cloud-init`** in the template and a compatible datasource).
3. **Run the workload as a small QEMU VM** — trade RAM/disk for **`cicustom`** and the same **`#cloud-config`** workflow as public clouds.

This greenfield stack uses **LXCs** for light services (Pi-hole, Tailscale, Omada). If you want **`user_data_file_id`**-style ergonomics from Terraform with minimal glue, prefer **QEMU templates** for those roles or keep **one** wrapper on the Proxmox node that maps VMID → snippet.

### Tailscale LXC (snippets)

The **`bpg/proxmox`** `proxmox_virtual_environment_container` resource does **not** attach `user_data` the way QEMU VMs do. Uploaded snippets must be applied on the node or in the guest (see above).

1. **`terraform apply`** refreshes **`local:snippets/pihole.yaml`**, **`tailscale.yaml`**, **`omada.yaml`** with interpolated values.
2. Set **`tailscale_auth_key`** (and **`ssh_public_key`**) in **`terraform.tfvars`** (gitignored). Optional: **`tailscale_advertise_routes`** (default `192.168.0.0/16`).
3. Apply the snippet with the playbook or **`attach_lxc_cloud_init_snippets.sh`** (**`pct push`** + **guest `cloud-init`**). Use **`man pct`** / your Proxmox docs for CLI syntax—not **`pct set --help`**.

**Automated apply (Ansible)** — from the repo root:

`ansible-playbook workloads/ansible/playbooks/lxc-apply-cloud-init-snippets.yml`

The Tailscale CT also gets **`TS_AUTHKEY`** in **`environment_variables`** when `tailscale_auth_key` is non-empty (useful for `pct exec` / debugging). **`terraform output lxc_cloud_init_snippet_ids`** shows the stored file ids.

### Pi-hole LXC checklist (VMID **201**)

Unattended install **requires** `/etc/pihole/setupVars.conf` **before** `bash … --unattended` — the rendered **`pihole.yaml`** snippet does that (plus **`PIHOLE_SKIP_OS_CHECK`**, **`systemd-resolved`** off, **`features.nesting`** on the CT). The **Web UI password** is **not** taken from `WEBPASSWORD` in `setupVars` (Pi-hole v5+ expects a hash there; v6 uses TOML). Cloud-init runs **`pihole setpassword`** after install using **`pihole_admin_password`** from Terraform (base64 in the snippet).

1. **`terraform apply`** — optional: **`pihole_lxc_ipv4`** (must be **CIDR**, e.g. **`192.168.5.2/24`** — bare `192.168.5.2` makes Proxmox return **400 invalid ipv4 network configuration**), **`pihole_lxc_gateway`**, **`pihole_admin_password`** in **`terraform.tfvars`** (defaults to **`brewnix123`** in the snippet if unset).
2. **Apply** the rendered snippet to the CT (**not** `qm set`): run **`lxc-apply-cloud-init-snippets.yml`** or **`attach_lxc_cloud_init_snippets.sh`** so **`user-data`** lands under **`/var/lib/cloud/seed/nocloud/`** and **`cloud-init`** runs inside the guest (see that playbook).
3. **OPNsense:** allow **UDP/TCP 53** from internal VLANs → **192.168.5.2**; **`workloads/terraform-opnsense/kea.tf`** sets DHCP **DNS** to **Pi-hole** (gateway second). Add **`/etc/dnsmasq.d/99-local.conf`** entries for **`tn.fyberlabs.com`** → OPNsense if you rebuild the CT (see **`pihole.yaml.tftpl`**).
4. If install still fails (e.g. **Pi-hole v6** behavior changes), run the [interactive installer](https://docs.pi-hole.net/main/basic-install/) once inside the CT and compare **`/etc/pihole/setupVars.conf`** to upstream docs.

**Web UI login:** use **`pihole_admin_password`** from **`terraform.tfvars`** (or **`brewnix123`** if unset). **Proxmox serial/console** to the LXC is **Linux**, not Pi-hole — log in as **`ansible`** (SSH key) or **`root`** if you set a password; the Pi-hole password only applies to the **/admin** web UI (e.g. `http://192.168.5.2/admin`).

**SSH local port forward** (e.g. `ssh -L 8443:192.168.5.2:443 fw`): the host **`fw` must reach** `192.168.5.2`. If **`fw` is Proxmox** and the node has **no IP on VLAN 50** (`vmbr3`), the tunnel target often **fails** — add a **management IP on `vmbr3`** (e.g. `192.168.5.254/24`), **SSH to a host on that subnet** (e.g. OPNsense `192.168.5.1` if SSH is enabled), or tunnel to **port 80** (`…:192.168.5.2:80`) if the UI is HTTP-only. From `fw`, test: **`curl -sI http://192.168.5.2/admin`**.

**Recovery — `curl` to `:80`/`:443` connection refused, `systemctl status pihole-FTL` not found:** Pi-hole **never finished installing** (common if cloud-init ran **before** the mgmt NIC/VLAN could reach the internet, or the unattended script failed). On **`fw`**:

```bash
pct exec 201 -- tail -80 /var/log/cloud-init-output.log
pct exec 201 -- tail -80 /var/log/pihole-unattended-install.log   # after next cloud-init run with updated snippet
```

Then **inside** the CT (**`pct enter 201`** or **`ssh ansible@192.168.5.2`**):

```bash
sudo systemctl disable --now systemd-resolved 2>/dev/null; sudo systemctl mask systemd-resolved 2>/dev/null
sudo bash -lc 'export PIHOLE_SKIP_OS_CHECK=true; curl -sSL https://install.pi-hole.net | bash -s -- --unattended'
# if that errors, run the same URL without --unattended once (interactive)
sudo pihole setpassword    # set UI password
sudo ss -tlnp | egrep ':80|:53|:443' || true
```

Re-push **`pihole.yaml`** from Terraform and **`cloud-init clean && reboot`** only if you want a full re-seed; manual install above is usually enough.

**Existing CT:** merge the **`dnsmasq.d`** fragment from **`pihole.yaml.tftpl`** into the running Pi-hole host (or re-render snippet + `pct`/cloud-init) so **`*.tn.fyberlabs.com`** resolves via OPNsense. To fix a wrong UI password without rebuilding: **`sudo pihole setpassword`**.

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
