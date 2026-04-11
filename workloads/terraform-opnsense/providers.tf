# OPNsense HTTPS API — create API key + secret in System → Access → Users.
# https://docs.opnsense.org/manual/how-tos/user.html#api-keys
#
# browningluke/opnsense: https://registry.terraform.io/providers/browningluke/opnsense/latest/docs
# Upstream: pre-v1.0; pin versions and read release notes before upgrades.

provider "opnsense" {
  uri             = var.opnsense_uri
  api_key         = var.opnsense_api_key
  api_secret      = var.opnsense_api_secret
  allow_insecure  = var.opnsense_allow_insecure
}
