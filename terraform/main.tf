# =============================================
# Cloud-Init Snippet Uploads (using correct syntax)
# =============================================
resource "proxmox_virtual_environment_file" "pihole_user_data" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node_name

  source_file {
    path = "${path.module}/cloud-init/pihole.yml"
    insecure = true
  }
}

resource "proxmox_virtual_environment_file" "tailscale_user_data" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node_name

  source_file {
    path = "${path.module}/cloud-init/tailscale.yml"
    insecure = true
  }
}

resource "proxmox_virtual_environment_file" "omada_user_data" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node_name

  source_file {
    path = "${path.module}/cloud-init/omada.yml"
    insecure = true
  }
}

# If opnsense_install_iso_file_id is unset, read the same id scripts/download_images.sh writes to
# images/validated_images.json (so apply works without -var-file=generated/... when the manifest exists).
locals {
  _opnsense_manifest_path = abspath("${path.module}/../images/validated_images.json")
  _opnsense_manifest      = fileexists(local._opnsense_manifest_path) ? jsondecode(file(local._opnsense_manifest_path)) : {}
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

  # Empty virtio disk has no bootloader → firmware falls through to iPXE ("no bootable disk").
  # CD on ide2 matches Proxmox UI defaults; ide3 often leaves the installer ISO missing or not first in boot order.
  # After install: set opnsense_install_iso_file_id = "" and apply (boot disk-only), or remove CD in UI.
  boot_order = local.opnsense_install_iso_attached ? ["ide2", "virtio0"] : ["virtio0"]

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
    bridge = "vmbr0"   # Fiber WAN (nic0)
    model  = "virtio"
  }

  network_device {
    bridge = "vmbr1"   # Starlink WAN (nic1)
    model  = "virtio"
  }

  network_device {
    bridge = "vmbr2"   # Main LAN (nic2)
    model  = "virtio"
  }

  network_device {
    bridge = "vmbr3"   # Camera Switch trunk
    model  = "virtio"
    trunks = "20;50"
  }

  network_device {
    bridge = "vmbr4"   # Full Omada trunk
    model  = "virtio"
    trunks = "10;20;30;40;50"
  }

  # OPNsense is FreeBSD-based — no cloud-init. If this VM ever had initialization.user_data,
  # removing it in Terraform can error (provider rebuild expects the old snippet volume).
  # We ignore that block; delete the small cloud-init/seed CD from VM 200 in the Proxmox UI once.
  lifecycle {
    ignore_changes = [initialization]
  }

  # Configure via installer console after ISO install.
}

# =============================================
# Pi-hole LXC
# (No user_account.keys here: clone + ssh-public-keys breaks on LXC config PUT — bpg/proxmox#1905.
#  Install the same key in the golden LXC template's /root/.ssh/authorized_keys before templating.)
# =============================================
resource "proxmox_virtual_environment_container" "pihole" {
  node_name = var.proxmox_node_name
  vm_id     = 201

  clone {
    vm_id = var.lxc_template_vmid
  }

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
    name   = "eth0"
    bridge = "vmbr2"
  }

  initialization {
    hostname = "pihole"

    ip_config {
      ipv4 {
        address = "192.168.0.10/16"
        gateway = "192.168.0.1"
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
    name   = "eth0"
    bridge = "vmbr4"
  }

  initialization {
    hostname = "tailscale"

    ip_config {
      ipv4 {
        address = "192.168.5.10/24"
      }
    }
  }
}

# =============================================
# Omada Controller LXC
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

  network_interface {
    name   = "eth0"
    bridge = "vmbr4"
  }

  initialization {
    hostname = "omada"

    ip_config {
      ipv4 {
        address = "192.168.5.20/24"
      }
    }
  }
}
