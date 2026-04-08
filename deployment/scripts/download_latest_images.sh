#!/usr/bin/env bash
# Deprecated entrypoint: greenfield downloader lives at repo-root scripts/download_images.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
echo "[INFO] Using greenfield script: $ROOT/scripts/download_images.sh" >&2
"$ROOT/scripts/download_images.sh" "$@"
mkdir -p "$ROOT/deployment/ansible/group_vars"
cp -f "$ROOT/images/validated_images.json" "$ROOT/deployment/ansible/group_vars/validated_images.json"
echo "[INFO] Mirrored manifest to deployment/ansible/group_vars/validated_images.json (legacy playbooks)." >&2
