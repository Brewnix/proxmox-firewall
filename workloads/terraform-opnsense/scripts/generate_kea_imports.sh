#!/usr/bin/env bash
# Query OPNsense Kea DHCPv4 API and emit Terraform resource blocks + terraform import lines.
#
# Usage (same auth as generate_alias_imports.sh):
#   export OPNSENSE_URI="https://192.168.5.1"
#   export OPNSENSE_API_KEY="..."
#   export OPNSENSE_API_SECRET="..."
#   # Optional: OPNSENSE_TLS_INSECURE=0
#   ./scripts/generate_kea_imports.sh > generated_kea.tf.snippet
#
# Requires Kea DHCP enabled and API access. Import order: subnets → reservations → peers.
#
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

SN_JSON="${TMPDIR}/search_subnet.json"
RS_JSON="${TMPDIR}/search_reservation.json"
PR_JSON="${TMPDIR}/search_peer.json"

if ! fetch_json "$SN_JSON" "${BASE}/api/kea/dhcpv4/searchSubnet?current=1&rowCount=9999" \
  "${BASE}/api/kea/dhcpv4/searchSubnet"; then
  echo "OPNsense API: kea/dhcpv4/searchSubnet failed (Kea installed and enabled?)" >&2
  exit 1
fi

if ! fetch_json "$RS_JSON" "${BASE}/api/kea/dhcpv4/searchReservation?current=1&rowCount=9999" \
  "${BASE}/api/kea/dhcpv4/searchReservation"; then
  echo '{"rows":[]}' > "$RS_JSON"
fi
if ! fetch_json "$PR_JSON" "${BASE}/api/kea/dhcpv4/searchPeer?current=1&rowCount=9999" \
  "${BASE}/api/kea/dhcpv4/searchPeer"; then
  echo '{"rows":[]}' > "$PR_JSON"
fi

export TF_DIR BASE KEY SEC CURL_TLS SN_JSON RS_JSON PR_JSON
export OPNSENSE_TLS_INSECURE="${OPNSENSE_TLS_INSECURE:-1}"

python3 <<'PY'
import json, os, re, subprocess

tf_dir = os.environ["TF_DIR"]
base = os.environ["BASE"].rstrip("/")
key = os.environ["KEY"]
sec = os.environ["SEC"]
tls_insecure = os.environ.get("OPNSENSE_TLS_INSECURE", "1") != "0"


def curl_get(url: str) -> dict:
    cmd = ["curl", "-sS"]
    if tls_insecure:
        cmd.append("-k")
    cmd.extend(["-u", f"{key}:{sec}", url])
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(p.stderr or "curl failed")
    return json.loads(p.stdout)


def slug(s: str, fb: str) -> str:
    s = (s or "").strip().lower()
    s = re.sub(r"[^a-z0-9]+", "_", s).strip("_")
    return s or fb


def tf_str(s) -> str:
    if s is None:
        return '""'
    return json.dumps(str(s))


def tf_bool(v) -> str:
    if v in (True, "true", "1", 1, "on", "yes"):
        return "true"
    return "false"


def flatten_selected(v):
    if v is None:
        return None
    if isinstance(v, str) and v:
        return v
    if isinstance(v, dict):
        if v.get("selected") is not None and str(v.get("selected")) not in ("", "0", "false"):
            return v.get("selected")
        for k, sub in v.items():
            if k == "selected":
                continue
            if isinstance(sub, dict) and sub.get("selected"):
                return k
        if len(v) == 1:
            return next(iter(v.keys()))
    return v


def list_from_option(val):
    """API may return list, comma string, or selected map list."""
    if val is None:
        return []
    if isinstance(val, list):
        return [str(x) for x in val if str(x).strip()]
    if isinstance(val, str):
        parts = re.split(r"[\n,;]+", val)
        return [p.strip() for p in parts if p.strip()]
    if isinstance(val, dict):
        out = []
        for k, sub in val.items():
            if isinstance(sub, dict) and sub.get("selected"):
                out.append(k)
            elif sub in (1, "1", True):
                out.append(k)
        return out if out else [str(k) for k in val.keys()]
    return [str(val)]


def unwrap(inner, *names):
    for n in names:
        if isinstance(inner, dict) and n in inner:
            inner = inner[n]
    return inner


def parse_subnet_payload(j: dict) -> dict:
    inner = unwrap(j, "subnet4", "dhcpv4")
    if isinstance(inner, dict) and "subnet" not in inner and "subnet4" in inner:
        inner = inner["subnet4"]
    return inner if isinstance(inner, dict) else {}


def parse_reservation_payload(j: dict) -> dict:
    inner = unwrap(j, "reservation", "dhcpv4")
    if isinstance(inner, dict) and "ip_address" not in inner and "reservation" in inner:
        inner = inner["reservation"]
    return inner if isinstance(inner, dict) else {}


def parse_peer_payload(j: dict) -> dict:
    inner = unwrap(j, "peer", "dhcpv4")
    if isinstance(inner, dict) and "name" not in inner and "peer" in inner:
        inner = inner["peer"]
    return inner if isinstance(inner, dict) else {}


def subnet_hcl(d: dict, name: str, uuid: str) -> str:
    od = d.get("option_data") or {}
    pools_raw = d.get("pools") or ""
    if isinstance(pools_raw, list):
        pool_lines = [str(x).strip() for x in pools_raw if str(x).strip()]
    else:
        pool_lines = [p.strip() for p in re.split(r"\r?\n", str(pools_raw)) if p.strip()]

    lines = [f'resource "opnsense_kea_subnet" "{name}" {{']
    lines.append(f"  subnet = {tf_str(d.get('subnet'))}")

    if pool_lines:
        lines.append("  pools = [")
        for p in pool_lines:
            lines.append(f"    {json.dumps(p)},")
        lines.append("  ]")

    mcid = d.get("match-client-id")
    if mcid is None:
        mcid = d.get("match_client_id")
    lines.append(f"  match_client_id = {tf_bool(mcid if mcid is not None else True)}")

    ac = d.get("option_data_autocollect")
    if ac is None:
        ac = od.get("option_data_autocollect")
    lines.append(f"  auto_collect = {tf_bool(ac if ac is not None else True)}")

    rtrs = list_from_option(od.get("routers"))
    if rtrs:
        lines.append("  routers = [")
        for r in rtrs:
            lines.append(f"    {json.dumps(r)},")
        lines.append("  ]")

    dns = list_from_option(od.get("domain_name_servers"))
    if dns:
        lines.append("  dns_servers = [")
        for r in dns:
            lines.append(f"    {json.dumps(r)},")
        lines.append("  ]")

    ds = list_from_option(od.get("domain_search"))
    if ds:
        lines.append("  domain_search = [")
        for r in ds:
            lines.append(f"    {json.dumps(r)},")
        lines.append("  ]")

    dn = od.get("domain_name") or ""
    if dn:
        lines.append(f"  domain_name = {tf_str(dn)}")

    ntp = list_from_option(od.get("ntp_servers"))
    if ntp:
        lines.append("  ntp_servers = [")
        for r in ntp:
            lines.append(f"    {json.dumps(r)},")
        lines.append("  ]")

    ts = list_from_option(od.get("time_servers"))
    if ts:
        lines.append("  time_servers = [")
        for r in ts:
            lines.append(f"    {json.dumps(r)},")
        lines.append("  ]")

    sr = od.get("static_routes") or ""
    if sr and str(sr).strip():
        # "dest,gw;dest2,gw2" or model-specific
        pieces = [x.strip() for x in str(sr).split(";") if x.strip()]
        blocks = []
        for piece in pieces:
            if "," in piece:
                dest, gw = piece.split(",", 1)
                blocks.append((dest.strip(), gw.strip()))
        for dest, gw in blocks:
            lines.append("  static_routes {")
            lines.append(f"    destination_ip = {json.dumps(dest)}")
            lines.append(f"    router_ip      = {json.dumps(gw)}")
            lines.append("  }")

    ns = d.get("next_server") or ""
    if ns:
        lines.append(f"  next_server = {tf_str(ns)}")

    tft = od.get("tftp_server_name") or ""
    if tft:
        lines.append(f"  tftp_server = {tf_str(tft)}")

    boot = od.get("boot_file_name") or ""
    if boot:
        lines.append(f"  tftp_bootfile = {tf_str(boot)}")

    desc = d.get("description") or ""
    if desc:
        lines.append(f"  description = {tf_str(desc)}")

    lines.append("}")
    return "\n".join(lines)


def reservation_hcl(d: dict, name: str) -> str:
    sid = flatten_selected(d.get("subnet"))
    lines = [f'resource "opnsense_kea_reservation" "{name}" {{']
    lines.append(f"  subnet_id   = {tf_str(sid)}")
    lines.append(f"  ip_address  = {tf_str(d.get('ip_address'))}")
    lines.append(f"  mac_address = {tf_str(d.get('hw_address'))}")
    hn = d.get("hostname") or ""
    if hn:
        lines.append(f"  hostname    = {tf_str(hn)}")
    desc = d.get("description") or ""
    if desc:
        lines.append(f"  description = {tf_str(desc)}")
    lines.append("}")
    return "\n".join(lines)


def peer_hcl(d: dict, name: str) -> str:
    role = flatten_selected(d.get("role"))
    role = str(role).lower() if role not in (None, "") else "primary"
    if role not in ("primary", "standby"):
        role = "primary"
    lines = [f'resource "opnsense_kea_peer" "{name}" {{']
    lines.append(f"  name = {tf_str(d.get('name'))}")
    lines.append(f"  url  = {tf_str(d.get('url'))}")
    lines.append(f'  role = "{role}"')
    lines.append("}")
    return "\n".join(lines)


used = set()


def tf_resource_label(prefix: str, label: str) -> str:
    """Terraform resource names must start with a letter or underscore (not a digit)."""
    base = slug(str(label), prefix)[:48]
    if not base:
        base = prefix
    if not (base[0].isalpha() or base[0] == "_"):
        base = f"{prefix}_{base}"[:60]
    return base


def uniq(prefix: str, label: str) -> str:
    base = tf_resource_label(prefix, label)
    n, i = base, 0
    while n in used:
        i += 1
        n = f"{base}_{i}"[:60]
    used.add(n)
    return n


with open(os.environ["SN_JSON"], encoding="utf-8") as f:
    sn_j = json.load(f)
with open(os.environ["RS_JSON"], encoding="utf-8") as f:
    rs_j = json.load(f)
with open(os.environ["PR_JSON"], encoding="utf-8") as f:
    pr_j = json.load(f)

sn_rows = sn_j.get("rows") or []
rs_rows = rs_j.get("rows") or []
pr_rows = pr_j.get("rows") or []

print(f"# Kea DHCPv4 — generated from {base}")
print(f"# Save into e.g. kea.tf, run terraform fmt, then imports below.")
print(f"# Directory: {tf_dir}")
print("")

print("# =============================================================================")
print("# opnsense_kea_subnet")
print("# =============================================================================")
print("")

sn_imports = []
for row in sn_rows:
    u = row.get("uuid")
    if not u:
        continue
    label = row.get("subnet") or row.get("description") or u[:8]
    name = uniq("kea_sn", str(label))
    try:
        raw = curl_get(f"{base}/api/kea/dhcpv4/getSubnet/{u}")
        d = parse_subnet_payload(raw)
        if not d.get("subnet"):
            print(f"# WARN uuid={u}: could not parse getSubnet, skipping HCL")
            continue
        print(subnet_hcl(d, name, u))
        print("")
        sn_imports.append((name, u))
    except Exception as e:
        print(f"# ERROR getSubnet {u}: {e}")

for name, u in sn_imports:
    print(f"terraform import 'opnsense_kea_subnet.{name}' '{u}'")

print("")
print("# =============================================================================")
print("# opnsense_kea_reservation")
print("# =============================================================================")
print("")

rs_imports = []
for row in rs_rows:
    u = row.get("uuid")
    if not u:
        continue
    label = f"{row.get('hw_address') or ''}_{row.get('ip_address') or ''}"
    name = uniq("kea_rs", label or u[:8])
    try:
        raw = curl_get(f"{base}/api/kea/dhcpv4/getReservation/{u}")
        d = parse_reservation_payload(raw)
        if not d.get("ip_address") or not d.get("hw_address"):
            print(f"# WARN uuid={u}: could not parse getReservation")
            continue
        print(reservation_hcl(d, name))
        print("")
        rs_imports.append((name, u))
    except Exception as e:
        print(f"# ERROR getReservation {u}: {e}")

for name, u in rs_imports:
    print(f"terraform import 'opnsense_kea_reservation.{name}' '{u}'")

print("")
print("# =============================================================================")
print("# opnsense_kea_peer")
print("# =============================================================================")
print("")

pr_imports = []
for row in pr_rows:
    u = row.get("uuid")
    if not u:
        continue
    label = row.get("name") or u[:8]
    name = uniq("kea_pr", str(label))
    try:
        raw = curl_get(f"{base}/api/kea/dhcpv4/getPeer/{u}")
        d = parse_peer_payload(raw)
        if not d.get("name") or not d.get("url"):
            print(f"# WARN uuid={u}: could not parse getPeer")
            continue
        print(peer_hcl(d, name))
        print("")
        pr_imports.append((name, u))
    except Exception as e:
        print(f"# ERROR getPeer {u}: {e}")

for name, u in pr_imports:
    print(f"terraform import 'opnsense_kea_peer.{name}' '{u}'")

if not pr_imports:
    print("# (no HA peers, or searchPeer unavailable)")
PY
