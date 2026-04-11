#!/usr/bin/env bash
# Run every `terraform import` line from generate_alias_imports.sh (batch).
#
# Same environment variables as generate_alias_imports.sh:
#   OPNSENSE_URI, OPNSENSE_API_KEY, OPNSENSE_API_SECRET
# Optional: OPNSENSE_TLS_INSECURE=0
#
# Run from anywhere:
#   ./scripts/import_firewall_aliases.sh
#
# If a resource is already in state, import fails — remove first:
#   terraform state rm 'opnsense_firewall_alias.alias_rfc1918'
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$TF_DIR"

while IFS= read -r line; do
  case "$line" in
    terraform\ import*)
      printf '%s\n' "$line"
      eval "$line"
      ;;
  esac
done < <("${SCRIPT_DIR}/generate_alias_imports.sh")
