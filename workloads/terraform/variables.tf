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
  default     = "192.168.5.0/24"
  description = "VLAN 50 (Management) — infra VMs (Pi-hole, Omada, Tailscale, etc.); gateway typically 192.168.5.1 on OPNsense."
}

variable "template_name" {
  description = "Golden Cloud-Init template"
  type        = string
  default     = "debian12-cloudinit-template" # or the VM name you used
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

variable "tailscale_auth_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = <<-EOT
    Tailscale reusable auth key (tskey-auth-... from https://login.tailscale.com/admin/settings/keys).
    Passed into cloud-init via Terraform templatefile (not a literal in the repo). Leave empty to skip automatic
    "tailscale up" in cloud-init; join manually or set this in terraform.tfvars and re-apply the snippet.
  EOT
}

variable "tailscale_advertise_routes" {
  type        = string
  default     = "192.168.0.0/16"
  description = "CIDR advertised with tailscale up --advertise-routes (subnet router)."
}

variable "pihole_lxc_ipv4" {
  type        = string
  default     = "192.168.5.2/24"
  description = "Pi-hole LXC IPv4 in CIDR form (Proxmox requires netmask), e.g. 192.168.5.2/24."

  validation {
    condition     = can(cidrhost(var.pihole_lxc_ipv4, 0))
    error_message = "pihole_lxc_ipv4 must be a valid IPv4 CIDR (e.g. 192.168.5.2/24), not a bare host address."
  }
}

variable "pihole_lxc_gateway" {
  type        = string
  default     = "192.168.5.1"
  description = "Default gateway for Pi-hole LXC (OPNsense on VLAN 50)."
}

variable "pihole_admin_password" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Pi-hole Web UI password for setupVars (unattended). If empty, cloud-init uses a placeholder; set in terraform.tfvars."
}

variable "opnsense_install_iso_file_id" {
  type        = string
  default     = ""
  description = <<-EOT
    Proxmox volume id for the decompressed DVD installer, e.g. local:iso/OPNsense-26.1-dvd-amd64.iso
    (upload under Datacenter → storage → ISO). Upstream ships OPNsense-*-dvd-amd64.iso.bz2; scripts/download_images.sh
    verifies checksums and bunzip2s to .iso. See docs/ISO_SOURCES.md.
    Leave empty after install so boot_order is disk-only.
  EOT
}
