output "opnsense_install_iso_effective" {
  description = "Proxmox volume id used for the OPNsense installer CD (variable or images/validated_images.json)."
  value       = local.opnsense_install_iso_effective != "" ? local.opnsense_install_iso_effective : "(none — run scripts/download_images.sh and sync, or set opnsense_install_iso_file_id)"
}

output "opnsense_install_iso_attached" {
  description = "Whether Terraform will attach a CDROM for install."
  value       = local.opnsense_install_iso_attached
}

output "lxc_cloud_init_snippet_ids" {
  description = "Proxmox file ids for uploaded cloud-init snippets (attach to LXC with pct set … cicustom user=… — see terraform/README.md)."
  value = {
    pihole    = proxmox_virtual_environment_file.pihole_user_data.id
    tailscale = proxmox_virtual_environment_file.tailscale_user_data.id
    omada     = proxmox_virtual_environment_file.omada_user_data.id
  }
}
