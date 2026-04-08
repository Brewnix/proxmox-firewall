# ISO and image sources (greenfield)

Automation for downloading and staging images lives in **`scripts/download_images.sh`**, with **`ansible/playbooks/sync_images_to_proxmox.yml`** to copy ISOs onto the node. Outputs feed **`terraform/`** via `terraform/generated/opnsense_install.auto.tfvars` (gitignored).

## End-to-end (greenfield)

```bash
./scripts/download_images.sh
ansible-playbook ansible/playbooks/sync_images_to_proxmox.yml
cd terraform && terraform apply -var-file=generated/opnsense_install.auto.tfvars
```

Optional flags on the script: `--with-proxmox-iso`, `--with-opnsense-raw` (.img.bz2), `--with-docker`, `--opnsense-version 26.1`.

## What gets downloaded (default)

| Artifact | Purpose |
|----------|---------|
| **OPNsense `*-OpenSSL-dvd-amd64.iso`** | Terraform **`opnsense_install_iso_file_id`** after upload (`local:iso/...`). |
| **Ubuntu LTS cloud `.img`** | Golden LXC / cloud-image workflows; paths in `validated_images.json`. |

Manifest: **`images/validated_images.json`** (under gitignored **`images/`**). Keys include **`opnsense_install_iso_file_id`**, **`opnsense_dvd_iso_relpath`**, **`ubuntu_image_relpath`**, and optional **`proxmox_*`** / **`opnsense_image_*`**.

## Legacy compatibility

**`deployment/scripts/download_latest_images.sh`** now delegates to **`scripts/download_images.sh`** and mirrors the same JSON to **`deployment/ansible/group_vars/validated_images.json`** so older playbooks that still read that path keep working without maintaining two implementations.

## Not the same: DVD ISO vs raw `.img.bz2`

- **DVD ISO** — Boot in Proxmox as a CD, install onto the empty virtio disk (Terraform VM). This is the **default** download.
- **`.img.bz2`** — Optional (`--with-opnsense-raw`); raw disk image, **not** substituted for the DVD install path unless you intentionally use a different workflow.

## Related docs

- **[DEVELOPMENT_INSTALL.md](DEVELOPMENT_INSTALL.md)** — environment setup; step 2 uses the new script path.
- **[PROXMOX_ANSWER_FILE.md](PROXMOX_ANSWER_FILE.md)** — Proxmox **host** auto-install ISO (optional `--with-proxmox-iso`), not OPNsense guest.
- **`terraform/README.md`** — Terraform + generated tfvars.
