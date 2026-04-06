variable "proxmox_api_token" {
  type        = string
  sensitive   = true
  description = "Proxmox API token (user@pam!tokenid=secret)"
}

variable "management_subnet" {
  default = "192.168.0.0/23"   # VLAN 10 Main Network for initial access
}

variable "vm_template" {
  default = "debian-12-cloudinit"   # Create this golden template with Packer later
}
