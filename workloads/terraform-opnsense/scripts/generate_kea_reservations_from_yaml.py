#!/usr/bin/env python3
"""
Emit opnsense_kea_reservation Terraform from network_devices.yaml (or compatible).

Maps each VLAN to opnsense_kea_subnet.<kea_sn_...> using the vlans[].subnet field.
IPs: use reserved_ip / ip / static_ip on the device if set; otherwise use --infer-ip
(stable hash into the DHCP pool range 10–250 per subnet).

Usage:
  ./scripts/generate_kea_reservations_from_yaml.py \\
    --yaml ../../network_devices.yaml \\
    --out ../generated_kea_reservations.tf

Requires: PyYAML (pip install pyyaml)
"""
from __future__ import annotations

import argparse
import hashlib
import ipaddress
import json
import re
import sys
from typing import Any, Iterator

try:
    import yaml
except ImportError as e:
    print("Missing PyYAML. Install with: pip install pyyaml", file=sys.stderr)
    raise SystemExit(1) from e


def subnet_to_kea_resource_name(subnet: str) -> str:
    """192.168.1.0/24 -> kea_sn_192_168_1_0_24"""
    s = subnet.strip().replace("/", "_").replace(".", "_")
    return f"kea_sn_{s}"


def slug(s: str, fallback: str) -> str:
    s = (s or "").strip().lower()
    s = re.sub(r"[^a-z0-9]+", "_", s).strip("_")
    return s or fallback


def tf_resource_label(prefix: str, label: str) -> str:
    """Terraform resource names must start with a letter or underscore."""
    base = slug(str(label), prefix)[:48]
    if not base:
        base = prefix
    if not (base[0].isalpha() or base[0] == "_"):
        base = f"{prefix}_{base}"[:60]
    return base


def normalize_mac(mac: str) -> str | None:
    m = str(mac).strip()
    if not m:
        return None
    m = m.upper().replace("-", ":")
    parts = re.split(r"[:]", m)
    if len(parts) != 6:
        return None
    try:
        return ":".join(f"{int(p, 16):02X}" for p in parts)
    except ValueError:
        return None


def parse_vlan(v: Any) -> int | None:
    if isinstance(v, int) and 1 <= v <= 4094:
        return v
    return None


def device_ip_field(obj: dict) -> str | None:
    for k in ("reserved_ip", "static_ip", "ip"):
        v = obj.get(k)
        if v is None:
            continue
        s = str(v).strip()
        if s:
            return s
    return None


def walk_devices(obj: Any, skip_keys: frozenset[str]) -> Iterator[dict]:
    """Yield dicts that look like inventory devices (have name + mac + vlan)."""
    if isinstance(obj, dict):
        name = obj.get("name")
        mac = obj.get("mac")
        vlan = parse_vlan(obj.get("vlan"))
        if (
            name is not None
            and mac is not None
            and vlan is not None
            and str(mac).strip()
        ):
            yield obj
        for k, v in obj.items():
            if k in skip_keys:
                continue
            yield from walk_devices(v, skip_keys)
    elif isinstance(obj, list):
        for x in obj:
            yield from walk_devices(x, skip_keys)


SKIP_TOP = frozenset({"vlans"})


def load_vlan_subnet_map(data: dict) -> dict[int, str]:
    out: dict[int, str] = {}
    for row in data.get("vlans") or []:
        if not isinstance(row, dict):
            continue
        v = parse_vlan(row.get("vlan"))
        sn = row.get("subnet")
        if v is None or not sn:
            continue
        out[v] = str(sn).strip()
    return out


def host_index_from_mac(mac: str, used: set[int]) -> int:
    """Pick a host index in [10, 250], stable per MAC, avoiding collisions within VLAN."""
    h = int(hashlib.sha256(mac.upper().encode()).hexdigest()[:8], 16)
    for attempt in range(1000):
        candidate = 10 + ((h + attempt) % 241)
        if candidate not in used:
            used.add(candidate)
            return candidate
    for c in range(10, 251):
        if c not in used:
            used.add(c)
            return c
    raise RuntimeError("VLAN pool exhausted (10–250)")


def ip_in_subnet(subnet_cidr: str, host_index: int) -> str:
    net = ipaddress.ip_network(subnet_cidr, strict=False)
    base = int(net.network_address)
    return str(ipaddress.ip_address(base + host_index))


def hostname_hint(name: str) -> str:
    return slug(name, "host")[:63]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument(
        "--yaml",
        required=True,
        help="Path to network_devices.yaml",
    )
    ap.add_argument(
        "--out",
        required=True,
        help="Write Terraform to this path (e.g. ../generated_kea_reservations.tf)",
    )
    ap.add_argument(
        "--infer-ip",
        action="store_true",
        help="Assign IPs in .10–.250 via stable hash when no reserved_ip/ip/static_ip",
    )
    args = ap.parse_args()

    with open(args.yaml, encoding="utf-8") as f:
        data = yaml.safe_load(f)
    if not isinstance(data, dict):
        print("YAML root must be a mapping", file=sys.stderr)
        raise SystemExit(2)

    vlan_subnets = load_vlan_subnet_map(data)
    if not vlan_subnets:
        print("No vlans: entries with vlan + subnet found; cannot map reservations.", file=sys.stderr)
        raise SystemExit(2)

    devices = list(walk_devices(data, SKIP_TOP))
    used_by_vlan: dict[int, set[int]] = {}
    # De-duplicate by MAC (keep first)
    seen_mac: set[str] = set()
    rows: list[tuple[dict, str, str]] = []
    for d in devices:
        mac_n = normalize_mac(str(d.get("mac", "")))
        if not mac_n:
            continue
        if mac_n in seen_mac:
            print(f"WARN: duplicate MAC skipped: {mac_n} ({d.get('name')})", file=sys.stderr)
            continue
        seen_mac.add(mac_n)
        vlan = parse_vlan(d.get("vlan"))
        if vlan is None:
            continue
        subnet = vlan_subnets.get(vlan)
        if not subnet:
            print(
                f"WARN: VLAN {vlan} has no subnet in vlans: — skip {d.get('name')!r}",
                file=sys.stderr,
            )
            continue
        explicit = device_ip_field(d)
        if explicit:
            try:
                ipaddress.ip_address(explicit.split("/")[0])
            except ValueError:
                print(f"WARN: bad IP on {d.get('name')!r}: {explicit}", file=sys.stderr)
                continue
            ip = explicit.split("/")[0]
        elif args.infer_ip:
            used: set[int] = used_by_vlan.setdefault(vlan, set())
            idx = host_index_from_mac(mac_n, used)
            ip = ip_in_subnet(subnet, idx)
        else:
            print(
                f"SKIP (no ip, use --infer-ip or add reserved_ip): {d.get('name')!r} vlan={vlan} mac={mac_n}",
                file=sys.stderr,
            )
            continue
        rows.append((d, mac_n, ip))

    used_names: set[str] = set()

    def uniq_name(prefix: str, label: str) -> str:
        base = tf_resource_label(prefix, label)
        n, i = base, 0
        while n in used_names:
            i += 1
            n = f"{base}_{i}"[:60]
        used_names.add(n)
        return n

    lines: list[str] = []
    lines.append("# =============================================================================")
    lines.append("# opnsense_kea_reservation (generated — do not commit; see .gitignore)")
    lines.append("# =============================================================================")
    if args.infer_ip:
        lines.append("# IPs: explicit reserved_ip/ip/static_ip where set; else inferred (review before apply).")
    else:
        lines.append("# IPs: only devices with reserved_ip, ip, or static_ip in the YAML.")
    lines.append(f"# Source: {args.yaml}")
    lines.append("")

    for d, mac_n, ip in rows:
        vlan = parse_vlan(d.get("vlan"))
        assert vlan is not None
        subnet = vlan_subnets[vlan]
        sn_res = subnet_to_kea_resource_name(subnet)
        name = str(d.get("name") or "device")
        res_name = uniq_name("kea_rs", f"{name}_{mac_n}")
        hn = hostname_hint(name)
        loc = d.get("location") or ""
        desc = f"{name}"
        if loc:
            desc = f"{name} ({loc})"

        lines.append(f'resource "opnsense_kea_reservation" "{res_name}" {{')
        lines.append(f"  subnet_id   = opnsense_kea_subnet.{sn_res}.id")
        lines.append(f"  ip_address  = {json.dumps(ip)}")
        lines.append(f"  mac_address = {json.dumps(mac_n)}")
        if hn:
            lines.append(f"  hostname    = {json.dumps(hn)}")
        lines.append(f"  description = {json.dumps(desc)}")
        lines.append("}")
        lines.append("")

    out_text = "\n".join(lines) + "\n"
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(out_text)

    print(f"Wrote {len(rows)} reservation(s) to {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
