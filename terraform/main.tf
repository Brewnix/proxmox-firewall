# =============================================
# Cloud-Init Snippet Uploads (using correct syntax)
# =============================================
resource "proxmox_virtual_environment_file" "opnsense_user_data" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node_name

  source_file {
    path = "${path.module}/cloud-init/opnsense.yml"
    insecure = true
  }
}

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

# =============================================
# OPNsense VM - Full VM
# =============================================
resource "proxmox_virtual_environment_vm" "opnsense" {
  node_name = var.proxmox_node_name
  vm_id     = 200
  name      = "opnsense"
  tags      = ["firewall", "opnsense"]

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

  initialization {
    datastore_id      = "local-lvm"
    user_data_file_id = proxmox_virtual_environment_file.opnsense_user_data.id
  }
}

# =============================================
# Pi-hole LXC
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

    user_account {
      keys = [var.ssh_public_key]
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

    user_account {
      keys = [var.ssh_public_key]
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

    user_account {
      keys = [var.ssh_public_key]
    }
  }
}
