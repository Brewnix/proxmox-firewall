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

variable "management_vlan_id" {
  type        = number
  default     = 50
  description = <<-EOT
    802.1Q tag on eth0 attached to lxc_bridge. Use 50 (or your mgmt VLAN) when OPNsense and clients share that tag.
    Use 0 for untagged: flat LAN (e.g. 192.168.0.x) on the bridge native VLAN — required for ARP to 192.168.0.1
    when the router is on untagged ports. If you set 192.168.0.x on the CT but leave this at 50, the CT
    still sends tagged VLAN 50 and ip neigh to the gateway shows FAILED.
  EOT
}

variable "lxc_bridge" {
  type        = string
  default     = "vmbr2"
  description = <<-EOT
    Linux bridge for Pi-hole / Tailscale / Omada LXCs. vmbr4 matches the "Omada trunk" layout in main.tf.
    For a flat 192.168.0.x home LAN where the Proxmox host and ISP router share nic2 (main LAN), use vmbr2
    so the CT shares L2 with 192.168.0.1. CTs on vmbr4 when the gateway only exists on vmbr2 get
    Destination Host Unreachable to the router — wrong bridge, not DNS.
  EOT
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
  description = "Default gateway for Pi-hole LXC. Use OPNsense on VLAN 50 (192.168.5.1) for the segmented design; use your ISP router (e.g. 192.168.0.1) only when the CT is on the same flat LAN as that router (see README: flat LAN bootstrap)."
}

variable "tailscale_lxc_ipv4" {
  type        = string
  default     = "192.168.5.10/24"
  description = "Tailscale LXC IPv4 CIDR (must match gateway subnet)."
  validation {
    condition     = can(cidrhost(var.tailscale_lxc_ipv4, 0))
    error_message = "tailscale_lxc_ipv4 must be a valid IPv4 CIDR."
  }
}

variable "tailscale_lxc_gateway" {
  type        = string
  default     = "192.168.5.1"
  description = "Default gateway for Tailscale LXC (same rules as pihole_lxc_gateway)."
}

variable "omada_lxc_ipv4" {
  type        = string
  default     = "192.168.5.20/24"
  description = "Omada LXC IPv4 CIDR (must match gateway subnet)."
  validation {
    condition     = can(cidrhost(var.omada_lxc_ipv4, 0))
    error_message = "omada_lxc_ipv4 must be a valid IPv4 CIDR."
  }
}

variable "omada_lxc_gateway" {
  type        = string
  default     = "192.168.5.1"
  description = "Default gateway for Omada LXC (same rules as pihole_lxc_gateway)."
}

variable "lxc_dns_servers" {
  type        = list(string)
  description = <<-EOT
    DNS servers Proxmox writes into these LXCs (initialization.dns). This is not “routing through OPNsense by
    choice” — it is whatever IP the CT will send DNS queries to. That only works if the CT has an IP route to
    that address (usually via its default gateway). For VLAN 50 + gateway 192.168.5.1, use 192.168.5.1 (Unbound)
    or public resolvers only if the firewall allows UDP/TCP 53 to them. For a flat LAN with gateway 192.168.0.1,
    use ["192.168.0.1"]. Do not use Pi-hole’s address here until Pi-hole is installed.
  EOT
  default     = ["192.168.5.1"]
}

variable "pihole_admin_password" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Pi-hole Web UI password. Applied after install via `pihole setpassword` (setupVars WEBPASSWORD is unreliable on v5+/v6). If empty, defaults to brewnix123 in the snippet — set in terraform.tfvars."
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
