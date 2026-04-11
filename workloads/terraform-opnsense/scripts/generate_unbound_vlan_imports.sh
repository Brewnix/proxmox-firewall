#!/usr/bin/env bash
# Query OPNsense API for VLANs + Unbound (host overrides, forwards, host aliases)
# and print Terraform resource blocks + terraform import lines.
#
# Usage (same auth as generate_alias_imports.sh):
#   export OPNSENSE_URI="https://192.168.5.1"
#   export OPNSENSE_API_KEY="..."
#   export OPNSENSE_API_SECRET="..."
#   # Optional: OPNSENSE_TLS_INSECURE=0
#   ./scripts/generate_unbound_vlan_imports.sh
#
# Copy the printed `resource` blocks into new .tf files in this directory, then run
# the `terraform import` lines (order: VLAN + host overrides first, then host aliases
# that reference parent overrides). Run `terraform fmt` and `terraform plan`.
#
# Domain overrides (`opnsense_unbound_domain_override`) are not listed here — the core
# API layout varies by version; add those manually from the registry if needed.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

URI="${OPNSENSE_URI:?set OPNSENSE_URI e.g. https://192.168.5.1}"
KEY="${OPNSENSE_API_KEY:?set OPNSENSE_API_KEY}"
SEC="${OPNSENSE_API_SECRET:?set OPNSENSE_API_SECRET}"

KEY="$(printf '%s' "$KEY" | tr -d '\r\n')"
SEC="$(printf '%s' "$SEC" | tr -d '\r\n')"
[[ "$KEY" == key=* ]] && KEY="${KEY#key=}"
[[ "$KEY" == KEY=* ]] && KEY="${KEY#KEY=}"
[[ "$SEC" == secret=* ]] && SEC="${SEC#secret=}"
[[ "$SEC" == SECRET=* ]] && SEC="${SEC#SECRET=}"

BASE="${URI%/}"

CURL_TLS=()
if [[ "${OPNSENSE_TLS_INSECURE:-1}" != "0" ]]; then
  CURL_TLS=(-k)
fi

JSON_BODY='{"current":1,"rowCount":9999}'

# $1=out file, $2=GET url, $3=POST url — writes JSON body, returns 0 if HTTP 200
fetch_json() {
  local out="$1" get_url="$2" post_url="$3"
  local HTTP
  HTTP=$(curl "${CURL_TLS[@]}" -sS -o "$out" -w '%{http_code}' \
    -u "${KEY}:${SEC}" \
    -H "Content-Type: application/json" \
    "$get_url") || true
  if [[ "$HTTP" != "200" ]]; then
    HTTP=$(curl "${CURL_TLS[@]}" -sS -o "$out" -w '%{http_code}' \
      -X POST \
      -u "${KEY}:${SEC}" \
      -H "Content-Type: application/json" \
      -d "$JSON_BODY" \
      "$post_url") || true
  fi
  [[ "$HTTP" == "200" ]]
}

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

VLAN_JSON="${TMPDIR}/vlan.json"
HO_JSON="${TMPDIR}/host_override.json"
FW_JSON="${TMPDIR}/forward.json"
HA_JSON="${TMPDIR}/host_alias.json"

ERR=0
fetch_json "$VLAN_JSON" "${BASE}/api/interfaces/vlan_settings/searchItem?current=1&rowCount=9999" \
  "${BASE}/api/interfaces/vlan_settings/searchItem" || { echo "OPNsense API: vlan_settings/searchItem failed" >&2; ERR=1; }
fetch_json "$HO_JSON" "${BASE}/api/unbound/settings/searchHostOverride?current=1&rowCount=9999" \
  "${BASE}/api/unbound/settings/searchHostOverride" || { echo "OPNsense API: unbound/searchHostOverride failed" >&2; ERR=1; }
fetch_json "$FW_JSON" "${BASE}/api/unbound/settings/searchForward?current=1&rowCount=9999" \
  "${BASE}/api/unbound/settings/searchForward" || { echo "OPNsense API: unbound/searchForward failed" >&2; ERR=1; }
fetch_json "$HA_JSON" "${BASE}/api/unbound/settings/searchHostAlias?current=1&rowCount=9999" \
  "${BASE}/api/unbound/settings/searchHostAlias" || { echo "OPNsense API: unbound/searchHostAlias failed" >&2; ERR=1; }

if [[ "$ERR" != "0" ]]; then
  echo "Fix API auth/TLS (see README and generate_alias_imports.sh)." >&2
  exit 1
fi

export TF_DIR VLAN_JSON HO_JSON FW_JSON HA_JSON
python3 <<'PY'
import json, os, re

tf_dir = os.environ["TF_DIR"]

def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def slug(s: str, fallback: str) -> str:
    s = (s or "").strip().lower()
    s = re.sub(r"[^a-z0-9]+", "_", s).strip("_")
    return s or fallback


def flatten_sel(v):
    """OPNsense grid often uses string or {selected: ...} / option maps."""
    if v is None:
        return None
    if isinstance(v, bool):
        return v
    if isinstance(v, (int, float)):
        return v
    if isinstance(v, str):
        return v
    if isinstance(v, dict):
        if "selected" in v and v["selected"] not in (None, ""):
            return v["selected"]
        # option map: pick key with truthy selected child
        for k, sub in v.items():
            if isinstance(sub, dict) and sub.get("selected"):
                return k
        # first key
        if v:
            return next(iter(v.keys()))
    return str(v)


def tf_bool(v) -> str:
    x = flatten_sel(v)
    if isinstance(x, bool):
        return "true" if x else "false"
    if x in (None, "", 0, "0"):
        return "false"
    s = str(x).lower()
    if s in ("1", "true", "yes", "on"):
        return "true"
    return "false"


def tf_str(s) -> str:
    if s is None:
        return '""'
    return json.dumps(str(s))


used_names = set()

def unique_tf_name(prefix: str, label: str) -> str:
    base = slug(label, prefix)[:48]
    n = base
    i = 0
    while n in used_names:
        i += 1
        n = f"{base}_{i}"[:60]
    used_names.add(n)
    return n


vlan_j = load(os.environ["VLAN_JSON"])
ho_j = load(os.environ["HO_JSON"])
fw_j = load(os.environ["FW_JSON"])
ha_j = load(os.environ["HA_JSON"])

vlan_rows = vlan_j.get("rows") or []
ho_rows = ho_j.get("rows") or []
fw_rows = fw_j.get("rows") or []
ha_rows = ha_j.get("rows") or []

print(f"# Generated from live OPNsense API — review before apply.")
print(f"# Working directory: {tf_dir}")
print(f"# 1) Save resource blocks below into e.g. interfaces_vlan.tf and unbound_dns.tf")
print(f"# 2) Run terraform fmt")
print(f"# 3) Run each terraform import line (host aliases after host overrides)")
print(f"# 4) terraform plan — expect no changes if UI matches .tf")
print("")

# --- VLAN ---
print("# =============================================================================")
print("# opnsense_interfaces_vlan")
print("# =============================================================================")
print("")

vlan_blocks = []
vlan_imports = []
for row in vlan_rows:
    u = row.get("uuid")
    if not u:
        continue
    tag = flatten_sel(row.get("tag"))
    parent = flatten_sel(row.get("if"))
    descr = flatten_sel(row.get("descr")) or flatten_sel(row.get("description")) or ""
    vlanif = flatten_sel(row.get("vlanif")) or ""
    pcp = flatten_sel(row.get("pcp"))
    try:
        tag_n = int(tag) if tag is not None else 0
    except (TypeError, ValueError):
        tag_n = 0
    try:
        prio = int(float(pcp)) if pcp is not None and str(pcp).strip() != "" else 0
    except (TypeError, ValueError):
        prio = 0

    label = f"{descr}_vlan{tag_n}" if descr else f"vlan_{parent}_{tag_n}"
    name = unique_tf_name("vlan", label)

    lines = [f'resource "opnsense_interfaces_vlan" "{name}" {{']
    lines.append(f"  description = {tf_str(descr)}")
    lines.append(f"  tag         = {tag_n}")
    lines.append(f"  priority    = {prio}")
    lines.append(f"  parent      = {tf_str(parent or '')}")
    if vlanif:
        lines.append(f"  device      = {tf_str(vlanif)}")
    lines.append("}")
    vlan_blocks.append("\n".join(lines))
    vlan_imports.append((name, u))

for b in vlan_blocks:
    print(b)
    print("")

for name, u in vlan_imports:
    print(f"terraform import 'opnsense_interfaces_vlan.{name}' '{u}'")

print("")

# --- Host overrides (skip nested alias rows: those use host_alias resource) ---
print("# =============================================================================")
print("# opnsense_unbound_host_override")
print("# =============================================================================")
print("")

ho_blocks = []
ho_imports = []
host_uuid_by_tf = {}  # tf resource name -> uuid (for alias comments)

for row in ho_rows:
    if row.get("isAlias"):
        continue
    u = row.get("uuid")
    if not u:
        continue
    host = flatten_sel(row.get("hostname")) or "*"
    dom = flatten_sel(row.get("domain")) or ""
    rr = flatten_sel(row.get("rr") or row.get("type")) or "A"
    if isinstance(rr, dict):
        rr = flatten_sel(rr) or "A"
    rr = str(rr).upper()
    if rr not in ("A", "AAAA", "MX"):
        rr = "A"

    enabled = tf_bool(row.get("enabled"))
    descr = flatten_sel(row.get("description")) or ""

    label = f"{host}.{dom}".strip(".")
    name = unique_tf_name("uh", label)

    lines = [f'resource "opnsense_unbound_host_override" "{name}" {{']
    lines.append(f"  enabled     = {enabled}")
    if descr:
        lines.append(f"  description = {tf_str(descr)}")
    lines.append(f"  hostname    = {tf_str(host)}")
    lines.append(f"  domain      = {tf_str(dom)}")
    lines.append(f'  type        = "{rr}"')

    if rr == "MX":
        mxp = flatten_sel(row.get("mxprio")) or flatten_sel(row.get("mx_priority")) or "10"
        mxh = flatten_sel(row.get("mx")) or flatten_sel(row.get("mx_host")) or ""
        try:
            mxpi = int(float(mxp))
        except (TypeError, ValueError):
            mxpi = 10
        lines.append(f"  mx_priority = {mxpi}")
        lines.append(f"  mx_host     = {tf_str(mxh)}")
    else:
        srv = flatten_sel(row.get("server")) or ""
        lines.append(f"  server      = {tf_str(srv)}")

    lines.append("}")
    ho_blocks.append("\n".join(lines))
    ho_imports.append((name, u))
    host_uuid_by_tf[name] = u

for b in ho_blocks:
    print(b)
    print("")

for name, u in ho_imports:
    print(f"terraform import 'opnsense_unbound_host_override.{name}' '{u}'")

print("")

# --- Forwards ---
print("# =============================================================================")
print("# opnsense_unbound_forward")
print("# =============================================================================")
print("")

fw_blocks = []
fw_imports = []

for row in fw_rows:
    u = row.get("uuid")
    if not u:
        continue
    dom = flatten_sel(row.get("domain")) or ""
    server = flatten_sel(row.get("server")) or ""
    port = flatten_sel(row.get("port")) or "53"
    verify = flatten_sel(row.get("verify")) or ""
    enabled = tf_bool(row.get("enabled"))
    try:
        port_n = int(float(port))
    except (TypeError, ValueError):
        port_n = 53

    label = f"fwd_{dom or 'all'}_{server}"
    name = unique_tf_name("fwd", label)

    lines = [f'resource "opnsense_unbound_forward" "{name}" {{']
    lines.append(f"  enabled     = {enabled}")
    lines.append(f"  domain      = {tf_str(dom)}")
    lines.append(f"  server_ip   = {tf_str(server)}")
    lines.append(f"  server_port = {port_n}")
    lines.append(f"  verify_cn   = {tf_str(verify)}")
    lines.append("}")
    fw_blocks.append("\n".join(lines))
    fw_imports.append((name, u))

for b in fw_blocks:
    print(b)
    print("")

for name, u in fw_imports:
    print(f"terraform import 'opnsense_unbound_forward.{name}' '{u}'")

print("")

# --- Host aliases (need parent override UUID in `override`) ---
print("# =============================================================================")
print("# opnsense_unbound_host_alias")
print("# =============================================================================")
print("")

ha_blocks = []
ha_imports = []

for row in ha_rows:
    u = row.get("uuid")
    if not u:
        continue
    parent = flatten_sel(row.get("host")) or ""
    host = flatten_sel(row.get("hostname")) or "*"
    dom = flatten_sel(row.get("domain")) or ""
    enabled = tf_bool(row.get("enabled"))
    descr = flatten_sel(row.get("description")) or ""

    label = f"alias_{host}.{dom}"
    name = unique_tf_name("ha", label)

    lines = [f'resource "opnsense_unbound_host_alias" "{name}" {{']
    lines.append(f"  override    = {tf_str(parent)}")
    lines.append(f"  enabled     = {enabled}")
    if descr:
        lines.append(f"  description = {tf_str(descr)}")
    lines.append(f"  hostname    = {tf_str(host)}")
    lines.append(f"  domain      = {tf_str(dom)}")
    lines.append("}")
    ha_blocks.append("\n".join(lines))
    ha_imports.append((name, u))

for b in ha_blocks:
    print(b)
    print("")

for name, u in ha_imports:
    print(f"terraform import 'opnsense_unbound_host_alias.{name}' '{u}'")

if not ha_imports:
    print("# (no host aliases)")
PY
