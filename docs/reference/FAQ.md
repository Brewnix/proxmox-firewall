# Frequently Asked Questions (FAQ)

## 🚀 General Questions

### What is Proxmox Firewall?

Proxmox Firewall is an enterprise-grade firewall solution built on Proxmox VE virtualization platform. It combines OPNsense firewall, Tailscale VPN, Suricata IDS/IPS, and Zeek network monitoring for comprehensive network security.

### What makes this different from other firewall solutions?

- **Infrastructure as Code**: Complete automation with Ansible and Terraform
- **Multi-site Management**: Easy deployment across multiple locations
- **Advanced Monitoring**: Built-in IDS/IPS and network analysis
- **VPN Integration**: Seamless Tailscale mesh networking
- **Open Source**: MIT licensed with full source code availability

### What hardware do I need?

**Minimum Requirements:**
- CPU: Intel N100 or equivalent
- RAM: 8GB
- Storage: 128GB SSD
- Network: 2x 2.5GbE ports

**Recommended:**
- CPU: Intel N305 or better
- RAM: 16GB+
- Storage: 256GB+ SSD
- Network: 4x 2.5GbE + 2x 10GbE SFP+

See our [Hardware Guide](../setup/HARDWARE.md) for detailed specifications.

## 🔧 Installation and Setup

### Can I test this without physical hardware?

Yes! We provide a comprehensive Docker test environment:

```bash
cd docker-test-framework
./run-integration-tests.sh -t example
```

This simulates the entire deployment without requiring physical hardware.

### How long does deployment take?

- **Docker test environment**: 10-15 minutes
- **Production deployment**: 30-60 minutes
- **Multi-site setup**: 1-2 hours per additional site

### Do I need to know Ansible/Terraform?

Not for basic usage. The project provides:
- Simple configuration scripts
- YAML-based site configuration
- Automated validation
- Comprehensive documentation

However, Ansible/Terraform knowledge helps for customization.

### What operating systems are supported?

**Control Machine (where you run the deployment):**
- Ubuntu 20.04+
- Debian 11+
- Other Linux distributions (with manual dependency installation)

**Target Hardware:**
- Proxmox VE (automatically installed via custom ISO)

## 🌐 Network Configuration

### How do I plan my network layout?

1. **Choose unique network prefixes** for each site (e.g., 10.1.x.x, 10.2.x.x)
2. **Plan VLAN structure**:
   - VLAN 10: Main LAN
   - VLAN 20: Cameras
   - VLAN 30: IoT devices
   - VLAN 40: Guest network
   - VLAN 50: Management

3. **Use our network planning guide**: [Network Configuration](../../config/NETWORK_PREFIX_FORMAT.md)

### Can I customize the VLAN layout?

Yes! Edit your site configuration file:

```yaml
site:
  hardware:
    network:
      vlans:
        - id: 10
          name: "main"
          subnet: "10.1.10.0/24"
        - id: 25
          name: "servers"  # Custom VLAN
          subnet: "10.1.25.0/24"
```

### How does multi-site connectivity work?

Sites connect via Tailscale mesh VPN:
- Each site advertises its subnet (e.g., 10.1.0.0/16)
- Automatic routing between sites
- Encrypted traffic over internet
- Zero-trust security model

## 🔐 Security

### How secure is this solution?

Very secure, with multiple layers:
- **Firewall**: Default-deny policy with explicit rules
- **IDS/IPS**: Real-time threat detection (Suricata)
- **Network Monitoring**: Deep packet inspection (Zeek)
- **VPN**: Encrypted site-to-site communication
- **Access Control**: SSH key authentication, API tokens

### Can I access services remotely?

Yes, via Tailscale VPN:
- Install Tailscale on your devices
- Access services via their Tailscale IPs
- No need to expose services to the internet
- Works from anywhere with internet

### What about compliance requirements?

The project follows industry standards:
- NIST Cybersecurity Framework
- CIS Controls
- OWASP security principles
- Comprehensive audit logging

## 🛠️ Troubleshooting

### My deployment failed, what should I do?

1. **Check the validation script**: `./validate-config.sh`
2. **Review logs**: Look for error messages in Ansible output
3. **Verify connectivity**: Ensure SSH access to Proxmox host
4. **Check our troubleshooting guide**: [Troubleshooting](../TROUBLESHOOTING.md)

### How do I get support?

1. **Documentation**: Check our comprehensive [docs](../README.md)
2. **GitHub Issues**: For bugs and feature requests
3. **GitHub Discussions**: For questions and community help
4. **Troubleshooting Guide**: Common issues and solutions

### VMs won't start, what's wrong?

Common causes:
- Insufficient storage space
- Missing VM templates
- Network configuration issues
- Resource allocation problems

See [VM Troubleshooting](../TROUBLESHOOTING.md#vm-deployment-issues) for detailed solutions.

## 🔌 Integration and Automation

### Can I integrate with my existing monitoring?

Yes! The project provides:
- **Prometheus metrics**: System and network metrics
- **Syslog integration**: Centralized logging
- **API access**: REST APIs for all components
- **Webhook support**: Real-time notifications

### How do I automate backups?

Backups are configured automatically:
- Daily VM snapshots
- Configurable retention periods
- Multiple storage backends (NFS, CIFS, CEPH)
- Automated cleanup

### Can I use this with other VPN solutions?

Currently optimized for Tailscale, but the project supports:
- **Headscale**: Self-hosted Tailscale alternative
- **Netbird**: Open-source mesh VPN
- **Custom VPN**: Via configuration modifications

## 💰 Cost and Licensing

### Is this free?

Yes! The project is MIT licensed and completely free to use, including:
- All source code
- Documentation
- Support community
- Updates and improvements

### What about commercial support?

While the project is open source, commercial support may be available through Fyber Labs Inc. Contact them for enterprise support options.

### Are there any ongoing costs?

Minimal ongoing costs:
- **Tailscale**: Free for personal use (up to 20 devices), paid plans for larger deployments
- **Hardware**: One-time purchase
- **Internet**: Standard internet connectivity
- **Optional**: Premium monitoring or backup services

## 🔄 Updates and Maintenance

### How do I update the system?

**Security updates**: Automatic by default
**System updates**: 
```bash
# Update Proxmox and VMs
ansible-playbook proxmox-local/ansible/site.yml --tags update
```

**Project updates**:
```bash
git pull origin main
./validate-config.sh
```

### How often should I update?

- **Security updates**: Automatic (weekly)
- **System updates**: Monthly
- **Project updates**: As needed (check releases)
- **Configuration reviews**: Quarterly

### What's the upgrade path?

The project maintains backward compatibility:
- Configuration files are versioned
- Automated migration scripts
- Clear upgrade documentation
- Rollback procedures

## 📊 Performance

### What throughput can I expect?

Performance depends on hardware:
- **2.5GbE**: Up to 2.5 Gbps
- **10GbE**: Up to 10 Gbps
- **CPU**: N100 can handle ~1-2 Gbps with IDS/IPS
- **N305**: Can handle ~5+ Gbps with full features

### How much bandwidth does monitoring use?

Monitoring overhead is minimal:
- **Suricata**: <1% CPU impact
- **Zeek**: <2% CPU impact
- **Tailscale**: <10MB/month per device
- **Logs**: ~100MB/day typical usage

### Can I scale this solution?

Yes, the architecture scales well:
- **Horizontal**: Add more sites easily
- **Vertical**: Upgrade hardware as needed
- **Services**: Enable/disable features per site
- **Load balancing**: Multiple OPNsense instances supported

---

## 📚 Still Have Questions?

If you don't find your answer here:

1. **Search our documentation**: [Complete Documentation](../README.md)
2. **Check GitHub Issues**: Someone may have asked the same question
3. **Create a new issue**: If you found a gap in our documentation
4. **Join discussions**: GitHub Discussions for community help

---

**Last Updated**: 2025-01-12  
**Have a question not covered here?** [Create an issue](https://github.com/Brewnix/proxmox-firewall/issues/new) to help us improve this FAQ! 
