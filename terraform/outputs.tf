output "opnsense_install_iso_effective" {
  description = "Proxmox volume id used for the OPNsense installer CD (variable or images/validated_images.json)."
  value       = local.opnsense_install_iso_effective != "" ? local.opnsense_install_iso_effective : "(none — run scripts/download_images.sh and sync, or set opnsense_install_iso_file_id)"
}

output "opnsense_install_iso_attached" {
  description = "Whether Terraform will attach a CDROM for install."
  value       = local.opnsense_install_iso_attached
}
