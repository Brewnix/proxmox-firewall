#!/usr/bin/env bash
# Query OPNsense API for firewall aliases and emit terraform import lines.
#
# Usage:
#   export OPNSENSE_URI="https://192.168.5.1"
#   export OPNSENSE_API_KEY="..."      # first line from apikey.txt — value only, no "key=" prefix
#   export OPNSENSE_API_SECRET="..."   # second line — value only, no "secret=" prefix
#   # Optional: OPNSENSE_TLS_INSECURE=0  — default is 1 (curl -k) for the default self-signed GUI cert
#   ./scripts/generate_alias_imports.sh
#
# API: OPNsense exposes list/search as searchItem (not "search"). See:
#   https://docs.opnsense.org/development/api/core/firewall.html
#
# Then run the printed `terraform import` commands from workloads/terraform-opnsense (with terraform init done).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

URI="${OPNSENSE_URI:?set OPNSENSE_URI e.g. https://192.168.5.1}"
KEY="${OPNSENSE_API_KEY:?set OPNSENSE_API_KEY}"
SEC="${OPNSENSE_API_SECRET:?set OPNSENSE_API_SECRET}"

# Trim whitespace; strip accidental "key=" / "secret=" prefixes from copy-paste
KEY="$(printf '%s' "$KEY" | tr -d '\r\n')"
SEC="$(printf '%s' "$SEC" | tr -d '\r\n')"
[[ "$KEY" == key=* ]] && KEY="${KEY#key=}"
[[ "$KEY" == KEY=* ]] && KEY="${KEY#KEY=}"
[[ "$SEC" == secret=* ]] && SEC="${SEC#secret=}"
[[ "$SEC" == SECRET=* ]] && SEC="${SEC#SECRET=}"

BASE="${URI%/}"
# Use curl --user so + / = in key/secret are encoded like Python requests.auth=(key, secret).
# Manual "Basic $(printf ... | base64)" often causes 401 with OPNsense keys.

CURL_TLS=()
# Default: allow self-signed (same as typical OPNsense HTTPS GUI). Set OPNSENSE_TLS_INSECURE=0 to verify CA.
if [[ "${OPNSENSE_TLS_INSECURE:-1}" != "0" ]]; then
  CURL_TLS=(-k)
fi

# Official action is searchItem — path /api/firewall/alias/search is wrong (404).
SEARCH_GET="${BASE}/api/firewall/alias/searchItem?current=1&rowCount=9999"
SEARCH_POST="${BASE}/api/firewall/alias/searchItem"
JSON_BODY='{"current":1,"rowCount":9999}'

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

HTTP_CODE=$(curl "${CURL_TLS[@]}" -sS -o "$TMP" -w '%{http_code}' \
  -u "${KEY}:${SEC}" \
  -H "Content-Type: application/json" \
  "$SEARCH_GET") || true
JSON="$(cat "$TMP")"

if [[ "$HTTP_CODE" != "200" ]]; then
  HTTP_CODE=$(curl "${CURL_TLS[@]}" -sS -o "$TMP" -w '%{http_code}' \
    -X POST \
    -u "${KEY}:${SEC}" \
    -H "Content-Type: application/json" \
    -d "$JSON_BODY" \
    "$SEARCH_POST") || true
  JSON="$(cat "$TMP")"
fi

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "OPNsense API HTTP ${HTTP_CODE} for firewall alias searchItem" >&2
  echo "Tried: GET ${SEARCH_GET}" >&2
  echo "Then:  POST ${SEARCH_POST} with ${JSON_BODY}" >&2
  echo "Response body:" >&2
  echo "$JSON" >&2
  echo >&2
  echo "Auth: curl -u \"\$OPNSENSE_API_KEY:\$OPNSENSE_API_SECRET\" (same as Terraform provider)." >&2
  echo "401 usually means: wrong key/secret, truncated copy (missing first/last chars), or secret missing trailing punctuation from apikey.txt." >&2
  echo "Paste line 1 and line 2 from the downloaded apikey.txt exactly." >&2
  echo "Set OPNSENSE_TLS_INSECURE=0 only with a proper CA; default uses curl -k." >&2
  exit 1
fi

export JSON TF_DIR
python3 <<'PY'
import json, os, sys

j = json.loads(os.environ["JSON"])
rows = j.get("rows") or []
tf_dir = os.environ["TF_DIR"]

# OPNsense "name" -> Terraform resource address (must match firewall_aliases.tf)
MAP = {
    "RFC1918": "opnsense_firewall_alias.alias_rfc1918",
    "LAN_NET": "opnsense_firewall_alias.alias_lan_net",
    "CAM_NET": "opnsense_firewall_alias.alias_cam_net",
    "IOT_NET": "opnsense_firewall_alias.alias_iot_net",
    "GUEST_NET": "opnsense_firewall_alias.alias_guest_net",
    "MGMT_NET": "opnsense_firewall_alias.alias_mgmt_net",
    "CLUSTER_NODE_NET": "opnsense_firewall_alias.alias_cluster_node_net",
    "CLUSTER_VM_NET": "opnsense_firewall_alias.alias_cluster_vm_net",
    "INTERNAL_NETS": "opnsense_firewall_alias.alias_internal_nets",
    "CAM_BLOCK_DEST": "opnsense_firewall_alias.alias_cam_block_dest",
    "HomeAssistant": "opnsense_firewall_alias.alias_home_assistant",
    "Dahua_NVR": "opnsense_firewall_alias.alias_dahua_nvr",
    "Reolink_Hub": "opnsense_firewall_alias.alias_reolink_hub",
    "TN_Doorbell": "opnsense_firewall_alias.alias_tn_doorbell",
    "Omada_Controller": "opnsense_firewall_alias.alias_omada_controller",
    "Ecobee_Thermostat": "opnsense_firewall_alias.alias_ecobee_thermostat",
    "Ecobee_Kitchen_Cam": "opnsense_firewall_alias.alias_ecobee_kitchen_cam",
    "Ecobee_Devices": "opnsense_firewall_alias.alias_ecobee_devices",
    "PiHole_DNS": "opnsense_firewall_alias.alias_pihole_dns",
    "Camera_Ports": "opnsense_firewall_alias.alias_camera_ports",
    "Omada_Mgmt": "opnsense_firewall_alias.alias_omada_mgmt",
    "Doorbell_WAN_Ports": "opnsense_firewall_alias.alias_doorbell_wan_ports",
}

by_name = {}
for row in rows:
    n = row.get("name")
    u = row.get("uuid")
    if n and u:
        by_name[n] = u

print("# Run from: " + tf_dir)
print("# terraform init  (if needed)")
print("")
for name, addr in sorted(MAP.items()):
    u = by_name.get(name)
    if not u:
        print(f"# MISSING on firewall (create via apply or UI): {name}")
        continue
    print(f"terraform import '{addr}' '{u}'")

mapped_names = set(MAP.keys())
present = set(by_name.keys())
unmapped = sorted(present - mapped_names)
if unmapped:
    print("")
    print("# --- Aliases on firewall not mapped in firewall_aliases.tf ---")
    for n in unmapped:
        print(f"# {n}  uuid={by_name[n]}")
PY
