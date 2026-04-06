variable "proxmox_api_token" {
  type        = string
  sensitive   = true
  description = "Proxmox API token (user@pam!tokenid=secret)"
}

variable "proxmox_node_name" {
  type        = string
  description = "Cluster node name from the Proxmox UI left tree (output of `hostname` on the host). Never use the node IP here."
  default     = "fw"
}

variable "management_subnet" {
  default = "192.168.0.0/23"   # VLAN 10 Main Network for initial access
}

variable "template_name" {
  description = "Golden Cloud-Init template"
  type        = string
  default     = "debian12-cloudinit-template"   # or the VM name you used
}

variable "lxc_template_vmid" {
  type        = number
  description = <<-EOT
    VMID of an existing LXC to clone (golden Debian CT). Use `pct list` on the node — QEMU VMs (e.g. 9000 debian12-cloudinit-template in the VM list) are not valid here; container clone requires `nodes/<node>/lxc/<vmid>.conf`.
    Create a CT from a vztmpl, configure it, convert to template, then set this to that CT's VMID.
  EOT
}

variable "ssh_public_key" {
  description = "SSH public key"
  type        = string
}
