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

variable "opnsense_allow_insecure" {
  type        = bool
  description = "Skip TLS verification (self-signed cert or HTTPS by IP when cert has no IP SAN). Set false when using a trusted CA or a hostname that matches the certificate. Same idea as curl -k / OPNSENSE_ALLOW_INSECURE."
  default     = true
}
