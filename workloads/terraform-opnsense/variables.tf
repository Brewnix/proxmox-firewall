variable "opnsense_uri" {
  type        = string
  description = "OPNsense management URL, e.g. https://192.168.5.1 (VLAN 50 mgmt)."
}

variable "opnsense_api_key" {
  type        = string
  sensitive   = true
  description = "OPNsense API key (public component)."
}

variable "opnsense_api_secret" {
  type        = string
  sensitive   = true
  description = "OPNsense API secret."
}
