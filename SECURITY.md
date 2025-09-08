# Security Policy

## 🛡️ Security Overview

The Proxmox Firewall project takes security seriously. This document outlines our security practices, how to report vulnerabilities, and security best practices for users.

## 🚨 Reporting Security Vulnerabilities

### How to Report

**DO NOT** create public issues for security vulnerabilities. Instead:

1. **Email**: Send details to `security@brewnix.com`
2. **Subject**: `[SECURITY] Proxmox Firewall - Brief Description`
3. **Include**:
   - Detailed description of the vulnerability
   - Steps to reproduce
   - Potential impact assessment
   - Suggested fix (if any)
   - Your contact information

### What to Expect

- **Acknowledgment**: Within 24 hours
- **Initial Assessment**: Within 72 hours
- **Status Updates**: Weekly until resolution
- **Fix Timeline**: Critical issues within 7 days, others within 30 days

### Responsible Disclosure

We follow responsible disclosure practices:
- We'll work with you to understand and validate the issue
- We'll develop and test a fix
- We'll coordinate public disclosure timing
- We'll credit you appropriately (if desired)

## 🔒 Security Features

### Network Security

**Firewall Protection:**
- OPNsense-based multi-layered firewall
- Default-deny policy with explicit allow rules
- VLAN segmentation and isolation
- Intrusion Detection/Prevention (Suricata)
- Network monitoring (Zeek)

**VPN Security:**
- WireGuard-based VPN (Tailscale)
- End-to-end encryption
- Zero-trust network access
- Subnet routing with ACLs

**Network Monitoring:**
- Real-time traffic analysis
- Threat detection and alerting
- SSL/TLS certificate validation
- Protocol anomaly detection

### System Security

**Access Control:**
- SSH key-based authentication
- API token authentication
- Role-based access control
- Multi-factor authentication support

**Infrastructure Security:**
- Automated security updates
- Secure credential management
- Encrypted configuration storage
- Audit logging

**Virtual Machine Security:**
- Isolated VM environments
- Secure VM templates
- Regular security patching
- Resource limitation and monitoring

## 🔐 Security Best Practices

### For Administrators

**Initial Setup:**
```bash
# Use strong SSH keys
ssh-keygen -t ed25519 -b 4096 -f ~/.ssh/proxmox-firewall

# Disable password authentication
ansible-playbook deployment/ansible/playbooks/02b_disable_root_password.yml

# Enable automatic security updates
ansible-playbook deployment/ansible/playbooks/enable_auto_updates.yml
```

**Network Configuration:**
- Use unique network prefixes for each site
- Implement proper VLAN segmentation
- Configure strong firewall rules
- Enable IDS/IPS monitoring
- Use VPN for all remote access

**Credential Management:**
- Store credentials in secure locations
- Use environment variables for secrets
- Rotate API tokens regularly
- Monitor credential usage

### For Users

**Configuration Security:**
```yaml
# Example secure site configuration
site:
  security:
    firewall:
      default_policy: "deny"
      enable_ids: true
      enable_ips: true
    vpn:
      enforce_acls: true
      require_authentication: true
    monitoring:
      enable_logging: true
      log_retention_days: 90
```

**Device Security:**
- Change default passwords on all devices
- Keep firmware updated
- Use secure protocols (HTTPS, SSH)
- Monitor device access logs

## 🚩 Common Security Issues

### Configuration Vulnerabilities

**Weak Network Segmentation:**
```yaml
# ❌ Bad: Overly permissive rules
firewall_rules:
  - action: allow
    source: any
    destination: any

# ✅ Good: Specific, restrictive rules
firewall_rules:
  - action: allow
    source: "10.1.10.0/24"
    destination: "10.1.10.100:445"
    protocol: tcp
```

**Exposed Services:**
```yaml
# ❌ Bad: Direct WAN exposure
vm_templates:
  service:
    network:
      wan_access: true

# ✅ Good: VPN-only access
vm_templates:
  service:
    network:
      vpn_only: true
      firewall_rules:
        - source: "tailscale"
          action: allow
```

### Deployment Security

**Insecure Credentials:**
```bash
# ❌ Bad: Hardcoded credentials
export PROXMOX_PASSWORD="admin123"

# ✅ Good: Secure credential files
export PROXMOX_API_SECRET="$(cat ~/.config/proxmox/api_token)"
```

**Unsecured Communication:**
```bash
# ❌ Bad: Unencrypted connections
../../brewnix.sh deployment site proxmox-firewall config/sites/<site_name>/firewall-site.yml

# ✅ Good: Secured connections with proper SSH keys
../../brewnix.sh deployment site proxmox-firewall config/sites/<site_name>/firewall-site.yml \
  --private-key ~/.ssh/proxmox-firewall \
  --ssh-extra-args="-o StrictHostKeyChecking=yes"
```

## 🔍 Security Monitoring

### Automated Monitoring

The system includes several security monitoring components:

**Suricata IDS/IPS:**
- Real-time traffic inspection
- Signature-based threat detection
- Automatic rule updates
- Alert generation and logging

**Zeek Network Monitor:**
- Deep packet inspection
- Protocol analysis
- Behavioral anomaly detection
- Connection tracking and logging

**System Monitoring:**
- Failed authentication attempts
- Unusual network traffic patterns
- Resource usage anomalies
- Configuration changes

### Log Analysis

**Important Log Locations:**
- OPNsense: `/var/log/filter.log`, `/var/log/suricata.log`
- Zeek: `/opt/zeek/logs/current/`
- System: `/var/log/auth.log`, `/var/log/syslog`
- Proxmox: `/var/log/pve/`

**Key Monitoring Queries:**
```bash
# Failed SSH attempts
grep "Failed password" /var/log/auth.log

# Firewall blocks
grep "block" /var/log/filter.log | tail -100

# Suricata alerts
grep "Priority: 1" /var/log/suricata.log

# Unusual network connections
zeek-cut < conn.log | awk '$7 > 10000' # Large data transfers
```

## 🛠️ Security Tools and Integration

### Vulnerability Scanning

**Network Scanning:**
```bash
# Scan for open ports
nmap -sS -O target_network/24

# Check for vulnerabilities
nmap --script vuln target_host
```

**Configuration Auditing:**
```bash
# Validate configuration security
./validate-config.sh --security-check

# Audit firewall rules
ansible-playbook tests/security_audit.yml
```

### Security Automation

**Automated Updates:**
- Enable automatic security updates for OS
- Configure automatic rule updates for Suricata
- Set up certificate renewal automation

**Incident Response:**
```bash
# Emergency lockdown
ansible-playbook security/emergency_lockdown.yml

# Isolate compromised system
ansible-playbook security/isolate_system.yml --limit compromised_host
```

## 📋 Security Checklist

### Initial Deployment
- [ ] SSH keys properly configured
- [ ] Password authentication disabled
- [ ] Firewall rules validated
- [ ] VPN connectivity tested
- [ ] IDS/IPS enabled and configured
- [ ] Monitoring systems active
- [ ] Backup systems tested
- [ ] Documentation reviewed

### Regular Maintenance
- [ ] Security updates applied
- [ ] Firewall rules reviewed
- [ ] Access logs monitored
- [ ] Vulnerability scans performed
- [ ] Backup integrity verified
- [ ] Incident response plan tested
- [ ] Security policies updated

### Incident Response
- [ ] Incident detected and classified
- [ ] Affected systems identified
- [ ] Containment measures implemented
- [ ] Evidence preserved
- [ ] Stakeholders notified
- [ ] Recovery plan executed
- [ ] Post-incident review conducted

## 🚀 Security Updates

### Supported Versions

| Version | Supported | Security Updates |
|---------|-----------|------------------|
| main    | ✅        | Yes              |
| dev     | ⚠️        | Limited          |
| archive | ❌        | No               |

### Update Process

1. **Security updates** are released as soon as possible
2. **Critical vulnerabilities** get emergency patches
3. **Minor issues** are included in regular releases
4. **Breaking changes** are clearly documented

## 📞 Emergency Contacts

For critical security issues requiring immediate attention:

- **Primary**: security@brewnix.com

---

For questions about this security policy, contact security@brewnix.com 
