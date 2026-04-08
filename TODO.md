# TODO

## In Progress

- Test on new hardware with limited resources
- Migrate proxmox-local-legacy and common to new ansible and terraform
- IP for proxmox needs to be dhcp to initialize then static in actual planned net (implemented, needs testing)
- Clean up testing to replicate live system
- Once everything is working we separate out a core of terraform and ansible for brewnix

## Fixes

- Proper proxmox TOML answer file jinja fixes/validation [docs](https://pve.proxmox.com/wiki/Automated_Installation)

## GitOps Implementation

- Create template repository structure with submodule management
- Implement GitHub Actions for automated deployments
- Create USB bootstrap process for GitHub connectivity
- Design secure state and credential management strategy
- Implement automated update mechanisms for deployed systems

## Documentation

- Create some sample mermaid network diagrams showing VLANs and example devices
- Validate API.md placeholder examples against real implementation details
- Validate TROUBLESHOOTING.md referenced commands
- Verify FAQ.md answers against actual implementation

## Features

- Zabbix SNMP VM
- Prometheus and snmp_exporter
- Grafana
- bsnmp for OPNSense?

## Automation

- Develop the update scripts for the non-package repo VM software ie. the curl based installers (if they don't add themselves to apt sources or similar solutions).
- VM backup health dashboard
- review accuracy of hardware validation and the hardware config playbook

## Multi-Site Improvements

- Support different network topologies per site
- Create global network sharing ansible examples for connecting networks by tailscale (terraform), headscale(terraform), and netbird(terraform) depending on site and a yet to be specified global network config.
- Support self-hosted VPN control plane/DNS - Specify DMZ, DMZ VM, cloud VM for headscale or self hosted netbird.

## Validation Tests

### Security Validation

- Test monitoring setup
  - Verify Zeek logging
  - Check Suricata rules
  - Validate log rotation
  - Test alert configuration
