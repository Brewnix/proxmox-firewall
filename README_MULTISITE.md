# Multi-Site Deployment Guide (Modern Workflow)

This guide explains how to manage and deploy multiple firewall sites using the recommended **template + submodule** approach with Proxmox Firewall.

---

## 🚀 Overview

- **Multi-site support** lets you manage any number of sites (locations, offices, homes, etc.) from a single infrastructure repository.
- **Recommended workflow:** Use the [proxmox-firewall-template](https://github.com/brewnix/proxmox-firewall-template) as your parent repo, with `proxmox-firewall` as a submodule in `vendor/`.
- **All site-specific configuration** lives in `config/sites/` and `config/devices/` in your parent repo. The submodule contains only code, playbooks, and templates.

> **See the [main README](README.md) for a high-level overview and project structure.**

---

## 🗂️ Example Directory Structure

```
my-infra-project/
├── config/
│   ├── sites/
│   │   ├── primary.yml
│   │   └── branch-office.yml
│   ├── devices/
│   │   ├── primary/
│   │   │   └── ...
│   │   └── branch-office/
│   │       └── ...
│   └── secrets/
├── .env
├── vendor/
│   └── proxmox-firewall/   # Submodule
├── README.md
└── ...
```

---

## 📝 Example Site Configs

`config/sites/primary.yml`:
```yaml
site:
  name: primary
  display_name: "Primary Home"
  network_prefix: 10.1
  domain: primary.local
  proxmox:
    host: 10.1.50.1
    node_name: pve
    storage_pool: local-lvm
    template_storage: local
  timezone: America/New_York
  # ... other site-specific settings ...
```

`config/sites/branch-office.yml`:
```yaml
site:
  name: branch-office
  display_name: "Branch Office"
  network_prefix: 10.2
  domain: branch.local
  proxmox:
    host: 10.2.50.1
    node_name: pve
    storage_pool: local-lvm
    template_storage: local
  timezone: America/Chicago
  # ... other site-specific settings ...
```

---

## ➕ Adding a New Site

1. **Create a new site config:**
   - Use the script for guided setup:
     ```bash
     ./vendor/proxmox-firewall/deployment/scripts/create_site_config.sh
     ```
   - Or copy and edit an existing file in `config/sites/`.
2. **Add device configs:**
   - Use the device script or edit YAML in `config/devices/<site_name>/`.
   - See [README_DEVICES.md](README_DEVICES.md) for details.
3. **Add any site-specific secrets to `.env`** (see below).

---

## 🚀 Deploying or Updating a Single Site

1. **Validate your config:**
   ```bash
   ./vendor/proxmox-firewall/validate-config.sh <site_name>
   ```
2. **Create the custom Proxmox ISO:**
   ```bash
   ansible-playbook vendor/proxmox-firewall/deployment/ansible/playbooks/create_proxmox_iso.yml -e site_name=<site_name>
   ```
3. **Install the ISO on your hardware.**
4. **Deploy the site with Ansible:**
   - For CI/testing:
     ```bash
     ansible-playbook vendor/proxmox-firewall/deployment/ansible/master_playbook.yml --limit=<site_name>
     ```
   - For production:
     ```bash
     cd vendor/proxmox-firewall/proxmox-local/ansible
     ansible-playbook site.yml --limit=<site_name>
     ```

---

## 🔄 Updating All Sites

- Make your code or template changes in the submodule.
- Validate and deploy to each site as above, one at a time.
- Use git branches or PRs for safe updates.

---

## 🛠️ Environment Variables and Per-Site Overrides

- The `.env` file in your parent repo holds secrets and credentials.
- For per-site values, use a naming convention like `PRIMARY_PROXMOX_HOST`, `BRANCH_OFFICE_PROXMOX_HOST`, etc.
- Scripts and playbooks will pick up the correct values based on the site name.

Example:
```bash
# .env
PRIMARY_PROXMOX_HOST=10.1.50.1
BRANCH_OFFICE_PROXMOX_HOST=10.2.50.1
PRIMARY_ADMIN_EMAIL=admin@primary.local
BRANCH_OFFICE_ADMIN_EMAIL=admin@branch.local
```

---

## 💡 Best Practices for Multi-Site & GitOps

- **Keep all site configs and secrets out of the submodule.**
- **Use a consistent VLAN and network design** across sites for easier management.
- **Pin the submodule** to a known-good release for stability.
- **Test changes on one site** before rolling out to all.
- **Use GitOps tools** (ArgoCD, Flux, GitHub Actions) to automate deployments.
- **Back up your config and state** regularly.

---

## 🔗 Cross-References

- [Main README](README.md)
- [Device Management](README_DEVICES.md)
- [Proxmox Answer File](docs/PROXMOX_ANSWER_FILE.md)
- [Submodule Strategy](docs/SUBMODULE_STRATEGY.md)

---

## ❓ Troubleshooting

- **Validation errors?** Run `./vendor/proxmox-firewall/validate-config.sh <site_name>` and check the output.
- **Deployment issues?** See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).
- **Need more help?** Open a GitHub issue or join the discussions.

---

> **This guide reflects the recommended, modern workflow. For legacy/manual instructions, see [docs/DEVELOPMENT_INSTALL.md](docs/DEVELOPMENT_INSTALL.md).**
