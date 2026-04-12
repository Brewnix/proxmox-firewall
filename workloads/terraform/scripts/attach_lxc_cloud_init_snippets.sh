#!/usr/bin/env bash
# Run on the Proxmox NODE as root after `terraform apply` uploads snippets to local:snippets.
# Seeds NoCloud inside each CT and runs cloud-init there (same idea as
# workloads/ansible/playbooks/lxc-apply-cloud-init-snippets.yml). Do not rely on
# `pct set --cicustom` alone for LXCs.
#
#   ./attach_lxc_cloud_init_snippets.sh
#
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root on the Proxmox node." >&2
  exit 1
fi

SNIPPETS_DIR=/var/lib/vz/snippets
NO_CLOUD=/var/lib/cloud/seed/nocloud

declare -a PAIRS=(
  "201:pihole.yaml:pihole"
  "202:tailscale.yaml:tailscale"
  "203:omada.yaml:omada"
)

for ent in "${PAIRS[@]}"; do
  vmid="${ent%%:*}"
  rest="${ent#*:}"
  snip="${rest%%:*}"
  host="${rest##*:}"

  echo "=== VMID ${vmid} (${snip}) ==="
  pct exec "${vmid}" -- bash -lc \
    'command -v cloud-init >/dev/null 2>&1 || (export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq cloud-init)'
  pct exec "${vmid}" -- mkdir -p "${NO_CLOUD}"
  pct exec "${vmid}" -- bash -c "printf 'instance-id: lxc-${vmid}\\nlocal-hostname: ${host}\\n' > ${NO_CLOUD}/meta-data"
  pct push "${vmid}" "${SNIPPETS_DIR}/${snip}" "${NO_CLOUD}/user-data"
  pct exec "${vmid}" -- cloud-init clean --logs || true
  pct exec "${vmid}" -- bash -lc 'cloud-init init --local && cloud-init modules --mode=config && cloud-init modules --mode=final'
  echo ""
done

echo "Done. Check /var/log/cloud-init-output.log inside each CT if something did not finish (e.g. Pi-hole curl install)."
