#!/usr/bin/env bash
# Greenfield image fetcher for repo-root terraform/ + ansible/.
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
TERRAFORM_GEN_DIR="$REPO_ROOT/terraform/generated"
PROXMOX_ISO_STORAGE_ID="${PROXMOX_ISO_STORAGE_ID:-local}"

mkdir -p "$IMAGES_DIR" "$LOGS_DIR" "$KEYS_DIR" "$TERRAFORM_GEN_DIR"
LOG_FILE="$LOGS_DIR/image_download_$(date +%Y%m%d_%H%M%S).log"

WITH_PROXMOX_ISO=0
WITH_OPNSENSE_RAW=0
WITH_DOCKER=0
OPNSENSE_VERSION="${OPNSENSE_VERSION:-}"

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
  echo "[INFO] $1" >>"$LOG_FILE"
}
log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
  echo "[WARN] $1" >>"$LOG_FILE"
}
log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
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
  ansible-playbook ansible/playbooks/sync_images_to_proxmox.yml
  cd terraform && terraform apply -var-file=generated/opnsense_install.auto.tfvars

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
  ver=$(curl -sS "https://api.github.com/repos/opnsense/core/releases/latest" | jq -r '.tag_name' | sed 's/^v//')
  if [[ -z "$ver" || "$ver" == "null" ]]; then
    ver="26.1"
    log_warn "Could not detect OPNsense version from GitHub; using fallback $ver"
  fi
  echo "$ver"
}

# OPNsense DVD ISO — used by Terraform opnsense_install_iso_file_id after upload to Proxmox.
validate_opnsense_dvd_iso() {
  local ver arch iso_name sha_url iso_url
  ver="$(resolve_opnsense_version)"
  arch="amd64"
  iso_name="OPNsense-${ver}-OpenSSL-dvd-${arch}.iso"
  iso_url="https://pkg.opnsense.org/releases/${ver}/${iso_name}"
  sha_url="https://pkg.opnsense.org/releases/${ver}/${iso_name}.sha256"

  log_info "OPNsense DVD ${ver} ($iso_name)"

  if ! curl -fsSL -o "$IMAGES_DIR/${iso_name}.sha256" "$sha_url"; then
    log_error "Failed to download SHA256 for $iso_name"
    return 1
  fi

  if [[ -f "$IMAGES_DIR/$iso_name" ]]; then
    if (cd "$IMAGES_DIR" && sha256sum -c "${iso_name}.sha256" 2>/dev/null); then
      log_info "Existing $iso_name already valid; skipping download"
    else
      log_warn "Existing $iso_name failed checksum; re-downloading"
      rm -f "$IMAGES_DIR/$iso_name"
    fi
  fi

  if [[ ! -f "$IMAGES_DIR/$iso_name" ]]; then
    if ! curl -fL -o "$IMAGES_DIR/$iso_name" "$iso_url"; then
      log_error "Failed to download $iso_url"
      return 1
    fi
  fi

  if ! (cd "$IMAGES_DIR" && sha256sum -c "${iso_name}.sha256" 2>/dev/null); then
    log_error "SHA256 verification failed for $iso_name"
    return 1
  fi

  update_json "opnsense_version" "$ver"
  update_json "opnsense_dvd_iso_filename" "$iso_name"
  update_json "opnsense_dvd_iso_abspath" "$IMAGES_DIR/$iso_name"
  update_json "opnsense_dvd_iso_relpath" "$(relpath_from_repo "$IMAGES_DIR/$iso_name")"
  update_json "opnsense_install_iso_file_id" "${PROXMOX_ISO_STORAGE_ID}:iso/${iso_name}"
  log_info "OPNsense DVD ISO OK → $IMAGES_DIR/$iso_name"
  return 0
}

validate_opnsense_raw_bz2() {
  local ver arch image_name base_url image_url sha256_url
  ver="$(resolve_opnsense_version)"
  arch="amd64"
  image_name="OPNsense-${ver}-OpenSSL-${arch}.img.bz2"
  base_url="https://mirror.ams1.nl.leaseweb.net/opnsense/releases/${ver}"
  image_url="${base_url}/${image_name}"
  sha256_url="${base_url}/OPNsense-${ver}-checksums-${arch}.sha256"

  log_info "OPNsense raw image $image_name (optional)"

  if ! curl -fL -o "$IMAGES_DIR/$image_name" "$image_url"; then
    log_error "Failed to download OPNsense raw $image_url"
    return 1
  fi
  if curl -fsSL -o "$IMAGES_DIR/opnsense-checksums-${ver}.sha256" "$sha256_url"; then
    if ! (cd "$IMAGES_DIR" && grep "$image_name" "opnsense-checksums-${ver}.sha256" | sha256sum -c - 2>/dev/null); then
      log_warn "SHA256 check failed for raw image (mirror layout may differ)"
    fi
  else
    log_warn "No checksum file for raw image"
  fi
  update_json "opnsense_image_path" "$IMAGES_DIR/$image_name"
  update_json "opnsense_image_relpath" "$(relpath_from_repo "$IMAGES_DIR/$image_name")"
  return 0
}

get_latest_ubuntu_lts() {
  local current_year short_year year
  current_year=$(date +%Y)
  for year in $(seq 2018 2 $((current_year + 2))); do
    short_year=$((year % 100))
    if curl -s --head "https://cloud-images.ubuntu.com/${short_year}.04/current/" | grep -q "200 OK"; then
      echo "${short_year}.04"
      return
    fi
  done
  echo "22.04"
}

validate_ubuntu_image() {
  local version=$1 arch image_name image_url sha256_url signature_url
  arch="amd64"
  image_name="ubuntu-${version}-server-cloudimg-${arch}.img"
  image_url="https://cloud-images.ubuntu.com/${version}/current/${image_name}"
  sha256_url="https://cloud-images.ubuntu.com/${version}/current/SHA256SUMS"
  signature_url="https://cloud-images.ubuntu.com/${version}/current/SHA256SUMS.gpg"

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
    log_warn "No opnsense_install_iso_file_id in manifest; skip terraform/generated"
    return 0
  fi
  local tfvars="$TERRAFORM_GEN_DIR/opnsense_install.auto.tfvars"
  cat >"$tfvars" <<EOF
# Generated by scripts/download_images.sh (gitignored pattern). From repo root:
#   cd terraform && terraform apply -var-file=generated/opnsense_install.auto.tfvars
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
    log_info "Done. Next: ansible-playbook ansible/playbooks/sync_images_to_proxmox.yml"
    log_info "Then: cd terraform && terraform apply -var-file=generated/opnsense_install.auto.tfvars"
    exit 0
  fi
  log_error "One or more steps failed"
  exit 1
}

main
