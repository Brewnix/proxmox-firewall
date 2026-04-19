# =============================================
# Cloud-Init Snippet Uploads (using correct syntax)
# =============================================
resource "proxmox_virtual_environment_file" "pihole_user_data" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node_name

  source_raw {
    file_name = "pihole.yaml"
    data = templatefile("${path.module}/cloud-init/pihole.yaml.tftpl", {
      ssh_public_key            = var.ssh_public_key
      pihole_lxc_ipv4           = var.pihole_lxc_ipv4
      pihole_lxc_gateway        = var.pihole_lxc_gateway
      pihole_admin_password_b64 = base64encode(var.pihole_admin_password != "" ? var.pihole_admin_password : "brewnix123")
    })
  }
}

resource "proxmox_virtual_environment_file" "tailscale_user_data" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node_name

  source_raw {
    file_name = "tailscale.yaml"
    data = templatefile("${path.module}/cloud-init/tailscale.yaml.tftpl", {
      ssh_public_key             = var.ssh_public_key
      tailscale_auth_key         = var.tailscale_auth_key
      tailscale_advertise_routes = var.tailscale_advertise_routes
    })
  }
}

resource "proxmox_virtual_environment_file" "omada_user_data" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node_name

  source_raw {
    file_name = "omada.yaml"
    data = templatefile("${path.module}/cloud-init/omada.yaml.tftpl", {
      ssh_public_key = var.ssh_public_key
    })
  }
}

# If opnsense_install_iso_file_id is unset, read the same id scripts/download_images.sh writes to
# images/validated_images.json (so apply works without -var-file=generated/... when the manifest exists).
locals {
  _opnsense_manifest_path        = abspath("${path.module}/../../images/validated_images.json")
  _opnsense_manifest             = fileexists(local._opnsense_manifest_path) ? jsondecode(file(local._opnsense_manifest_path)) : {}
  opnsense_install_iso_effective = trimspace(var.opnsense_install_iso_file_id) != "" ? trimspace(var.opnsense_install_iso_file_id) : trimspace(try(tostring(local._opnsense_manifest["opnsense_install_iso_file_id"]), ""))
  opnsense_install_iso_attached  = local.opnsense_install_iso_effective != ""
}

# =============================================
# OPNsense VM - Full VM
# =============================================
resource "proxmox_virtual_environment_vm" "opnsense" {
  node_name = var.proxmox_node_name
  vm_id     = 200
  name      = "opnsense"
  tags      = ["firewall", "opnsense"]

  # Boot disk first, CD second: installed system always boots virtio0; empty disk has no bootloader → firmware
  # tries the next entry (installer ISO on ide2). CD-first would prefer the ISO even when the disk is bootable.
  # CD on ide2 matches Proxmox defaults. After install: set opnsense_install_iso_file_id = "" and apply (disk-only).
  boot_order = local.opnsense_install_iso_attached ? ["virtio0", "ide2"] : ["virtio0"]

  dynamic "cdrom" {
    for_each = local.opnsense_install_iso_attached ? [1] : []
    content {
      file_id   = local.opnsense_install_iso_effective
      interface = "ide2"
    }
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 6144
  }

  disk {
    datastore_id = "local-lvm"
    size         = 32
    interface    = "virtio0"
  }

  network_device {
    bridge = "vmbr0" # Fiber WAN (nic0)
    model  = "virtio"
  }

  network_device {
    bridge = "vmbr1" # Starlink WAN (nic1)
    model  = "virtio"
  }

  network_device {
    bridge = "vmbr2" # LAN switch (nic2) — VLAN-aware trunk; native VLAN 10 for untagged devices
    model  = "virtio"
    trunks = "10;20;30;50;60;70"
  }

  network_device {
    bridge = "vmbr3" # Omada AP trunk (nic3) — all WiFi VLANs
    model  = "virtio"
    trunks = "10;20;30;40;50"
  }

  network_device {
    bridge = "vmbr4" # Camera Switch (nic4) — cameras + IoT + mgmt
    model  = "virtio"
    trunks = "20;30;50"
  }

  # Proxmox may still show a cloud-init / seed drive on this VM (provider `initialization` or the UI), but
  # OPNsense is FreeBSD — it does **not** consume Linux cloud-init user-data like Ubuntu cloud images.
  # `ignore_changes` avoids apply fighting that block; remove a stray seed CD in the UI if you do not want it.
  #
  # Linux guests in this stack are **LXCs** (Pi-hole, Tailscale, Omada): Terraform uploads cloud-init snippets
  # only; it does **not** attach them to CTs. After apply, run Ansible
  # workloads/ansible/playbooks/lxc-apply-cloud-init-snippets.yml or scripts/attach_lxc_cloud_init_snippets.sh (see README).
  lifecycle {
    ignore_changes = [initialization]
  }

  # Configure OPNsense via installer console after ISO install — not cloud-init.
}

# =============================================
# Pi-hole LXC
# (No user_account.keys here: clone + ssh-public-keys breaks on LXC config PUT — bpg/proxmox#1905.
#  Install the same key in the golden LXC template's /root/.ssh/authorized_keys before templating.)
#
# VLAN 50 (192.168.5.0/24) — management / network services (see network_devices.yaml):
#   .1  OPNsense (configure on firewall; not Terraform)
#   .2  Pi-hole (DNS for DHCP clients once OPNsense points to it)
#   .10 Tailscale
#   .20 Omada Controller
#   .30+ reserved for future infra on this VLAN
# =============================================
resource "proxmox_virtual_environment_container" "pihole" {
  node_name = var.proxmox_node_name
  vm_id     = 201

  clone {
    vm_id = var.lxc_template_vmid
  }

  # Pi-hole installer and FTL binding :53 are unreliable in unprivileged CTs; template default is often unprivileged.
  unprivileged = false

  cpu {
    cores = 2
  }

  memory {
    dedicated = 1024
  }

  disk {
    datastore_id = "local-lvm"
    size         = 8
  }

  network_interface {
    name    = "eth0"
    bridge  = var.lxc_bridge
    # 0 = untagged (flat 192.168.0.x on native VLAN). Non-zero = 802.1Q tag (e.g. 50 for mgmt VLAN).
    vlan_id = var.management_vlan_id == 0 ? null : var.management_vlan_id
  }

  # Recommended for Pi-hole/dnsmasq in unprivileged or strict profiles; safe on privileged CTs too.
  features {
    nesting = true
  }

  initialization {
    hostname = "pihole"

    dns {
      servers = var.lxc_dns_servers
    }

    ip_config {
      ipv4 {
        address = var.pihole_lxc_ipv4
        gateway = var.pihole_lxc_gateway
      }
    }
  }
}

# =============================================
# Tailscale LXC
# =============================================
resource "proxmox_virtual_environment_container" "tailscale" {
  node_name = var.proxmox_node_name
  vm_id     = 202

  clone {
    vm_id = var.lxc_template_vmid
  }

  # tailscaled needs /dev/net/tun; unprivileged CTs often fail to start the daemon or join. Match common Proxmox + Tailscale guidance.
  unprivileged = false

  cpu {
    cores = 1
  }

  memory {
    dedicated = 512
  }

  disk {
    datastore_id = "local-lvm"
    size         = 4
  }

  network_interface {
    name    = "eth0"
    bridge  = var.lxc_bridge
    vlan_id = var.management_vlan_id == 0 ? null : var.management_vlan_id
  }

  features {
    nesting = true
  }

  # TUN device for tailscaled is configured via Ansible in lxc-apply-cloud-init-snippets.yml
  # (lxc.cgroup2.devices.allow + lxc.mount.entry). See:
  # https://forum.proxmox.com/threads/how-to-enable-tun-tap-in-a-lxc-container.25339/

  # Tailscale also reads TS_AUTHKEY from the environment (useful for manual pct exec / debugging).
  environment_variables = var.tailscale_auth_key != "" ? { TS_AUTHKEY = var.tailscale_auth_key } : {}

  initialization {
    hostname = "tailscale"

    dns {
      servers = var.lxc_dns_servers
    }

    ip_config {
      ipv4 {
        address = var.tailscale_lxc_ipv4
        gateway = var.tailscale_lxc_gateway
      }
    }
  }
}

# =============================================
# Omada Controller LXC
# Omada discovers EAPs via L2 broadcast/multicast. It needs an interface on every
# bridge that carries AP traffic so it shares the same broadcast domain. eth0 is the
# management/default-route NIC; eth1/eth2 are trunk legs for AP discovery only.
# =============================================
resource "proxmox_virtual_environment_container" "omada" {
  node_name = var.proxmox_node_name
  vm_id     = 203

  clone {
    vm_id = var.lxc_template_vmid
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "local-lvm"
    size         = 16
  }

  # eth0 — management LAN (default route, Omada web UI)
  network_interface {
    name    = "eth0"
    bridge  = var.lxc_bridge
    vlan_id = var.management_vlan_id == 0 ? null : var.management_vlan_id
  }

  # eth1 — Omada AP trunk (vmbr3 / nic3) for EAP L2 discovery
  network_interface {
    name   = "eth1"
    bridge = "vmbr3"
  }

  # eth2 — Camera Switch (vmbr4 / nic4) for PoE-switch AP discovery
  network_interface {
    name   = "eth2"
    bridge = "vmbr4"
  }

  initialization {
    hostname = "omada"

    dns {
      servers = var.lxc_dns_servers
    }

    ip_config {
      ipv4 {
        address = var.omada_lxc_ipv4
        gateway = var.omada_lxc_gateway
      }
    }
  }
}
