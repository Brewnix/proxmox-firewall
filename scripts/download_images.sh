#!/usr/bin/env bash
# Greenfield image fetcher for workloads/terraform + proxmox/ansible/.
# Downloads OPNsense DVD ISO (Terraform install), Ubuntu cloud img, optional Proxmox host ISO / raw OPNsense / Docker.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck disable=SC2034
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

IMAGES_DIR="${IMAGES_DIR:-$REPO_ROOT/images}"
LOGS_DIR="${LOGS_DIR:-$REPO_ROOT/logs}"
KEYS_DIR="${KEYS_DIR:-$REPO_ROOT/keys}"
JSON_OUT="${JSON_OUT:-$IMAGES_DIR/validated_images.json}"
TERRAFORM_GEN_DIR="$REPO_ROOT/workloads/terraform/generated"
PROXMOX_ISO_STORAGE_ID="${PROXMOX_ISO_STORAGE_ID:-local}"

mkdir -p "$IMAGES_DIR" "$LOGS_DIR" "$KEYS_DIR" "$TERRAFORM_GEN_DIR"
LOG_FILE="$LOGS_DIR/image_download_$(date +%Y%m%d_%H%M%S).log"

WITH_PROXMOX_ISO=0
WITH_OPNSENSE_RAW=0
WITH_DOCKER=0
OPNSENSE_VERSION="${OPNSENSE_VERSION:-}"

# All user-visible log lines go to stderr so stdout stays clean for $(command) captures.
log_info() {
  echo -e "${GREEN}[INFO]${NC} $1" >&2
  echo "[INFO] $1" >>"$LOG_FILE"
}
log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1" >&2
  echo "[WARN] $1" >>"$LOG_FILE"
}
log_error() {
  echo -e "${RED}[ERROR]${NC} $1" >&2
  echo "[ERROR] $1" >>"$LOG_FILE"
}

check_command() {
  if ! command -v "$1" &>/dev/null; then
    log_error "Required command '$1' not found"
    exit 1
  fi
}

usage() {
  cat <<'USAGE'
Usage: scripts/download_images.sh [options]

Downloads to ./images/ and writes ./images/validated_images.json (paths relative to repo root in JSON).

Options:
  --with-proxmox-iso     Also download latest Proxmox VE installer ISO (large).
  --with-opnsense-raw    Also download OPNsense .img.bz2 (raw image, not for VM CD install).
  --with-docker          Also docker pull legacy test images (requires Docker).
  --opnsense-version V   Pin OPNsense release (e.g. 26.1). Default: latest GitHub core tag.

Environment:
  OPNSENSE_VERSION       Same as --opnsense-version.
  PROXMOX_ISO_STORAGE_ID Terraform storage id for generated tfvars (default: local).

After download:
  ansible-playbook proxmox/ansible/playbooks/sync_images_to_proxmox.yml
  cd workloads/terraform && terraform apply -var-file=generated/opnsense_install.auto.tfvars

USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-proxmox-iso) WITH_PROXMOX_ISO=1 ;;
    --with-opnsense-raw) WITH_OPNSENSE_RAW=1 ;;
    --with-docker) WITH_DOCKER=1 ;;
    --opnsense-version)
      OPNSENSE_VERSION="$2"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

check_command curl
check_command jq
check_command sha256sum
check_command gpg
check_command bzip2

echo "{}" >"$JSON_OUT"

update_json() {
  local key=$1
  local value=$2
  local temp
  temp="$(mktemp)"
  jq --arg key "$key" --arg value "$value" '.[$key] = $value' "$JSON_OUT" >"$temp"
  mv "$temp" "$JSON_OUT"
}

relpath_from_repo() {
  local abs="$1"
  echo "${abs#"$REPO_ROOT"/}"
}

resolve_opnsense_version() {
  if [[ -n "$OPNSENSE_VERSION" ]]; then
    echo "$OPNSENSE_VERSION"
    return
  fi
  local ver
  ver=$(curl -sS -H "User-Agent: brewnix-proxmox-firewall-scripts" \
    "https://api.github.com/repos/opnsense/core/releases/latest" | jq -r '.tag_name // empty' | sed 's/^v//')
  if [[ -n "$ver" && "$ver" != "null" ]]; then
    echo "$ver"
    return
  fi
  local try
  for try in 26.1.2 26.1 25.7 24.7 24.1; do
    if curl -sfI -o /dev/null "https://pkg.opnsense.org/releases/${try}/OPNsense-${try}-checksums-amd64.sha256"; then
      log_warn "Could not read OPNsense version from GitHub; using first matching release on pkg.opnsense.org: $try"
      echo "$try"
      return
    fi
  done
  log_warn "Using hardcoded fallback 25.7 (pkg.opnsense.org)"
  echo "25.7"
}

# Verify artifact using OPNsense checksum file format: SHA256 (filename) = <hex>
verify_opnsense_checksum_line() {
  local sums_file=$1 artifact_name=$2 filepath=$3
  local line expected actual
  line=$(grep -F "(${artifact_name})" "$sums_file" | head -1) || return 1
  expected=$(echo "$line" | sed 's/.*= //' | tr -d '\r\n[:space:]')
  actual=$(sha256sum "$filepath" | awk '{print $1}')
  [[ -n "$expected" && "$expected" == "$actual" ]]
}

# OPNsense ships DVD as .iso.bz2 + OPNsense-<ver>-checksums-amd64.sha256 (not OpenSSL-dvd.iso nor per-file .sha256).
validate_opnsense_dvd_iso() {
  local ver arch bz2_name iso_name base sums_url bz2_url sums_file
  ver="$(resolve_opnsense_version)"
  arch="amd64"
  bz2_name="OPNsense-${ver}-dvd-${arch}.iso.bz2"
  iso_name="OPNsense-${ver}-dvd-${arch}.iso"
  base="https://pkg.opnsense.org/releases/${ver}"
  sums_url="${base}/OPNsense-${ver}-checksums-${arch}.sha256"
  bz2_url="${base}/${bz2_name}"
  sums_file="$IMAGES_DIR/OPNsense-${ver}-checksums-${arch}.sha256"

  log_info "OPNsense DVD ${ver}: fetch $bz2_name → decompress to $iso_name"

  local need_bz2=1
  if ! curl -fsSL -o "$sums_file" "$sums_url"; then
    log_error "No checksums at $sums_url (wrong version? try OPNSENSE_VERSION=26.1.2 or 25.7)"
    return 1
  fi

  if [[ -f "$IMAGES_DIR/$bz2_name" ]]; then
    if verify_opnsense_checksum_line "$sums_file" "$bz2_name" "$IMAGES_DIR/$bz2_name"; then
      need_bz2=0
      log_info "Existing $bz2_name checksum OK"
    else
      log_warn "Existing $bz2_name bad checksum; re-downloading"
      rm -f "$IMAGES_DIR/$bz2_name"
    fi
  fi

  if [[ "$need_bz2" -eq 1 ]]; then
    if ! curl -fL -o "$IMAGES_DIR/$bz2_name" "$bz2_url"; then
      log_error "Failed to download $bz2_url"
      return 1
    fi
  fi

  if ! verify_opnsense_checksum_line "$sums_file" "$bz2_name" "$IMAGES_DIR/$bz2_name"; then
    log_error "SHA256 verification failed for $bz2_name"
    return 1
  fi

  if [[ ! -f "$IMAGES_DIR/$iso_name" ]]; then
    log_info "Decompressing $bz2_name (bunzip2 -k)…"
    bunzip2 -fk "$IMAGES_DIR/$bz2_name"
  fi

  if [[ ! -f "$IMAGES_DIR/$iso_name" ]]; then
    log_error "Expected $iso_name after decompress"
    return 1
  fi

  update_json "opnsense_version" "$ver"
  update_json "opnsense_dvd_bz2_relpath" "$(relpath_from_repo "$IMAGES_DIR/$bz2_name")"
  update_json "opnsense_dvd_iso_filename" "$iso_name"
  update_json "opnsense_dvd_iso_abspath" "$IMAGES_DIR/$iso_name"
  update_json "opnsense_dvd_iso_relpath" "$(relpath_from_repo "$IMAGES_DIR/$iso_name")"
  update_json "opnsense_install_iso_file_id" "${PROXMOX_ISO_STORAGE_ID}:iso/${iso_name}"
  log_info "OPNsense DVD ISO OK → $IMAGES_DIR/$iso_name"
  return 0
}

validate_opnsense_raw_bz2() {
  local ver arch image_name base sums_url image_url sums_file
  ver="$(resolve_opnsense_version)"
  arch="amd64"
  image_name="OPNsense-${ver}-vga-${arch}.img.bz2"
  base="https://pkg.opnsense.org/releases/${ver}"
  sums_url="${base}/OPNsense-${ver}-checksums-${arch}.sha256"
  image_url="${base}/${image_name}"
  sums_file="$IMAGES_DIR/OPNsense-${ver}-checksums-${arch}.sha256"

  log_info "OPNsense VGA raw image $image_name (optional)"

  if ! curl -fsSL -o "$sums_file" "$sums_url"; then
    log_error "Failed to download checksums $sums_url"
    return 1
  fi
  if ! curl -fL -o "$IMAGES_DIR/$image_name" "$image_url"; then
    log_error "Failed to download $image_url"
    return 1
  fi
  if verify_opnsense_checksum_line "$sums_file" "$image_name" "$IMAGES_DIR/$image_name"; then
    log_info "Raw image checksum OK"
  else
    log_warn "SHA256 verification failed for $image_name"
  fi
  update_json "opnsense_image_path" "$IMAGES_DIR/$image_name"
  update_json "opnsense_image_relpath" "$(relpath_from_repo "$IMAGES_DIR/$image_name")"
  return 0
}

get_latest_ubuntu_lts() {
  # Use stable release tree (…/releases/VV.04/release/…); /current/ often 404s from mirrors or older LTS layout.
  local short v url
  for short in $(seq 32 -2 14); do
    v="${short}.04"
    url="https://cloud-images.ubuntu.com/releases/${v}/release/ubuntu-${v}-server-cloudimg-amd64.img"
    if curl -sfI -o /dev/null "$url"; then
      echo "$v"
      return
    fi
  done
  echo "22.04"
}

validate_ubuntu_image() {
  local version=$1 arch image_name image_url sha256_url signature_url base
  arch="amd64"
  image_name="ubuntu-${version}-server-cloudimg-${arch}.img"
  base="https://cloud-images.ubuntu.com/releases/${version}/release"
  image_url="${base}/${image_name}"
  sha256_url="${base}/SHA256SUMS"
  signature_url="${base}/SHA256SUMS.gpg"

  log_info "Ubuntu cloud image ${version}"

  if ! gpg --list-keys "Ubuntu Cloud Image Signing Key" &>/dev/null; then
    gpg --keyserver keyserver.ubuntu.com --recv-keys 0x843938DF228D22F7B3742BC0D94AA3F0EFE21092 2>/dev/null || true
  fi
  curl -fsSL -o "$IMAGES_DIR/SHA256SUMS" "$sha256_url" || return 1
  curl -fsSL -o "$IMAGES_DIR/SHA256SUMS.gpg" "$signature_url" || true
  gpg --verify "$IMAGES_DIR/SHA256SUMS.gpg" "$IMAGES_DIR/SHA256SUMS" 2>/dev/null || log_warn "Ubuntu SHA256SUMS GPG verify skipped/failed"

  if ! curl -fL -o "$IMAGES_DIR/$image_name" "$image_url"; then
    log_error "Failed to download Ubuntu image"
    return 1
  fi
  (cd "$IMAGES_DIR" && grep "$image_name" SHA256SUMS | sha256sum -c - 2>/dev/null) || log_warn "Ubuntu checksum line verify failed"

  update_json "ubuntu_version" "$version"
  update_json "ubuntu_image_path" "$IMAGES_DIR/$image_name"
  update_json "ubuntu_image_relpath" "$(relpath_from_repo "$IMAGES_DIR/$image_name")"
  return 0
}

validate_proxmox_iso() {
  local latest_iso iso_url sha256_url
  log_info "Latest Proxmox VE ISO"
  latest_iso=$(curl -s --insecure "http://download.proxmox.com/iso/" | grep -o 'proxmox-ve_[0-9]\+\.[0-9]\+-[0-9]\+\.iso' | sort -V | tail -n 1)
  if [[ -z "$latest_iso" ]]; then
    log_error "Could not parse latest Proxmox ISO name"
    return 1
  fi
  iso_url="http://download.proxmox.com/iso/$latest_iso"
  sha256_url="http://download.proxmox.com/iso/${latest_iso}.sha256sum"
  curl -fL -o "$IMAGES_DIR/$latest_iso" "$iso_url" || return 1
  if curl -fsSL -o "$IMAGES_DIR/${latest_iso}.sha256sum" "$sha256_url"; then
    (cd "$IMAGES_DIR" && sha256sum -c "${latest_iso}.sha256sum" 2>/dev/null) || log_warn "Proxmox ISO checksum verify failed"
  fi
  update_json "proxmox_version" "$latest_iso"
  update_json "proxmox_iso_path" "$IMAGES_DIR/$latest_iso"
  update_json "proxmox_iso_relpath" "$(relpath_from_repo "$IMAGES_DIR/$latest_iso")"
  return 0
}

validate_docker_image() {
  local image=$1 tag=$2 full_image="${image}:${tag}"
  log_info "Docker pull $full_image"
  docker pull "$full_image" || return 1
  local digest
  digest=$(docker inspect --format='{{.RepoDigests}}' "$full_image" | grep -o '@sha256:[a-f0-9]*' | head -1 || true)
  update_json "docker_${image//\//_}_${tag}" "${full_image}${digest}"
  return 0
}

write_terraform_fragment() {
  local iso_id
  iso_id=$(jq -r '.opnsense_install_iso_file_id // empty' "$JSON_OUT")
  if [[ -z "$iso_id" ]]; then
    log_warn "No opnsense_install_iso_file_id in manifest; skip workloads/terraform/generated"
    return 0
  fi
  local tfvars="$TERRAFORM_GEN_DIR/opnsense_install.auto.tfvars"
  cat >"$tfvars" <<EOF
# Generated by scripts/download_images.sh (gitignored pattern). From repo root:
#   cd workloads/terraform && terraform apply -var-file=generated/opnsense_install.auto.tfvars
# After OPNsense is installed on virtio0, remove or empty opnsense_install_iso_file_id and apply again.
opnsense_install_iso_file_id = "${iso_id}"
EOF
  log_info "Wrote $tfvars"
}

write_manifest_meta() {
  update_json "generated_at_utc" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  update_json "repo_root" "$REPO_ROOT"
}

main() {
  local failed=0
  log_info "Repo root: $REPO_ROOT"
  log_info "Output JSON: $JSON_OUT"

  validate_opnsense_dvd_iso || failed=1

  local uver
  uver="$(get_latest_ubuntu_lts)"
  log_info "Detected Ubuntu LTS: $uver"
  validate_ubuntu_image "$uver" || failed=1

  if [[ "$WITH_OPNSENSE_RAW" -eq 1 ]]; then
    validate_opnsense_raw_bz2 || failed=1
  fi

  if [[ "$WITH_PROXMOX_ISO" -eq 1 ]]; then
    validate_proxmox_iso || failed=1
  fi

  if [[ "$WITH_DOCKER" -eq 1 ]]; then
    check_command docker
    local docker_images=(
      "crowdsecurity/crowdsec:latest"
      "postgres:13"
      "nginx:alpine"
      "redis:alpine"
    )
    local img
    for img in "${docker_images[@]}"; do
      validate_docker_image "${img%:*}" "${img#*:}" || failed=1
    done
  fi

  write_manifest_meta
  write_terraform_fragment

  if [[ "$failed" -eq 0 ]]; then
    log_info "Done. Next: ansible-playbook proxmox/ansible/playbooks/sync_images_to_proxmox.yml"
    log_info "Then: cd workloads/terraform && terraform apply -var-file=generated/opnsense_install.auto.tfvars"
    exit 0
  fi
  log_error "One or more steps failed"
  exit 1
}

main
