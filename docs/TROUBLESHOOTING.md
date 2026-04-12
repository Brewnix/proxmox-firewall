# Troubleshooting Guide

> **Note:** If you are using the submodule/template workflow, prefix all script paths in this guide with `vendor/proxmox-firewall/` (e.g., `./vendor/proxmox-firewall/validate-config.sh`).

This guide covers common issues and their solutions for the Proxmox Firewall project.

## 🚀 Quick Diagnostics

### System Health Check
```bash
# Run comprehensive validation
./vendor/proxmox-firewall/validate-config.sh

# Check Ansible connectivity
ansible all -m ping -i deployment/ansible/inventory/

# Test configuration syntax
yamllint config/sites/
ansible-lint deployment/ansible/
```

### Service Status Check
```bash
# Check Proxmox services
systemctl status pve-cluster pveproxy pvedaemon

# Check network interfaces
ip link show
bridge link show

# Check VMs
qm list
```

## 🔧 Installation Issues

### Prerequisites Installation Fails

**Problem**: `./vendor/proxmox-firewall/deployment/scripts/prerequisites.sh` fails with package errors

**Solution**:
```bash
# Update package lists
sudo apt update

# Fix broken packages
sudo apt --fix-broken install

# Install manually if needed
sudo apt install python3-pip ansible terraform

# Check Python environment
python3 --version
pip3 --version
```

### SSH Key Issues

**Problem**: "Permission denied (publickey)" errors

**Solution**:
```bash
# Check SSH key permissions
ls -la ~/.ssh/
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub

# Test SSH connection
ssh -v user@proxmox-host

# Add key to agent
ssh-add ~/.ssh/id_rsa

# Verify key in .env file
grep SSH .env
```

### Ansible Connection Failures

**Problem**: Ansible can't connect to Proxmox hosts

**Common Causes & Solutions**:

1. **SSH Key Not Configured**:
   ```bash
   # Copy SSH key to target host
   ssh-copy-id root@proxmox-host
   
   # Or manually add to authorized_keys
   cat ~/.ssh/id_rsa.pub | ssh root@proxmox-host 'cat >> ~/.ssh/authorized_keys'
   ```

2. **Wrong Inventory Configuration**:
   ```yaml
   # Check deployment/ansible/inventory/hosts.yml
   all:
     hosts:
       proxmox-host:
         ansible_host: 192.168.1.100
         ansible_user: root
         ansible_ssh_private_key_file: ~/.ssh/id_rsa
   ```

3. **Firewall Blocking SSH**:
   ```bash
   # Check if SSH port is open
   nmap -p 22 proxmox-host
   
   # Allow SSH through firewall
   ufw allow 22
   ```

## 🌐 Network Configuration Issues

### VLAN Configuration Problems

**Problem**: VLANs not working correctly

**Diagnostics**:
```bash
# Check VLAN configuration
cat /etc/network/interfaces

# Test VLAN connectivity
ping -I vlan10 10.1.10.1

# Check bridge configuration
brctl show
```

**Solution**:
```bash
# Restart networking
systemctl restart networking

# Recreate VLANs if needed
ansible-playbook deployment/ansible/playbooks/03_network_setup.yml
```

### IP Address Conflicts

**Problem**: IP address conflicts causing connectivity issues

**Diagnostics**:
```bash
# Check for duplicate IPs
nmap -sn 10.1.10.0/24

# Check ARP table
arp -a

# Verify DHCP leases
cat /var/lib/dhcp/dhcpd.leases
```

**Solution**:
1. Update site configuration with unique network prefixes
2. Clear DHCP leases: `rm /var/lib/dhcp/dhcpd.leases`
3. Restart network services

### Bridge Interface Issues

**Problem**: Network bridges not working

**Diagnostics**:
```bash
# Check bridge status
brctl show
ip link show type bridge

# Check bridge forwarding
cat /proc/sys/net/bridge/bridge-nf-call-iptables
```

**Solution**:
```bash
# Recreate bridges
ansible-playbook deployment/ansible/playbooks/03_network_setup.yml --tags bridges

# Enable bridge forwarding
echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables
```

## 🖥️ VM Deployment Issues

### Terraform Failures

**Problem**: Terraform can't create VMs

**Common Issues**:

1. **Invalid API Credentials**:
   ```bash
   # Test API access
   curl -k https://proxmox-host:8006/api2/json/version \
     -H "Authorization: PVEAPIToken=USER@REALM!TOKENID=SECRET"
   
   # Check .env file
   grep PROXMOX_API .env
   ```

2. **Insufficient Storage**:
   ```bash
   # Check storage usage
   pvesm status
   df -h
   
   # Clean up old VMs/templates
   qm list
   qm destroy VMID
   ```

3. **Template Missing**:
   ```bash
   # List templates
   qm list | grep template
   
   # Recreate templates
   ansible-playbook deployment/ansible/playbooks/04_vm_templates.yml
   ```

4. **Host firewall (UFW) blocks the API (`EOF` on HTTPS to `:8006`)** — If **`ufw`** is enabled on the **Proxmox node**, default rules often **deny** inbound **TCP 8006** from the LAN. **`dmesg`** shows **`[UFW BLOCK] ... DPT=8006`** from your workstation IP. **Terraform**, **curl**, and the **web UI** then fail or drop mid-connection. On the node:
   ```bash
   ufw status numbered
   ufw allow from 192.168.0.0/24 to any port 8006 proto tcp comment 'Proxmox API from LAN'
   ufw reload
   # Also allow SSH from the same net if you lock the box down: port 22
   ```
   Adjust the source CIDR to your management network. Prefer **restrictive** rules, not `ufw allow 8006/tcp` from **anywhere**, if the host has WAN-facing interfaces.

   **Still blocking?** (a) Confirm **`ufw reload`** ran after changes. (b) **`ufw status verbose`** — verify an **ALLOW** for **8006** is listed *and* matches **from** your client subnet. (c) Traffic arrives on **`vmbr2`** — try an interface-specific allow: **`ufw allow in on vmbr2 from 192.168.0.0/24 to any port 8006 proto tcp`**, then **`ufw reload`**. (d) Duplicate or mis-ordered rules — **`ufw status numbered`**, **`ufw delete <n>`** on stale DENY or wrong ALLOW, re-add. (e) From **console**, **`ufw disable`** briefly — if blocks stop, only UFW ordering/content is wrong (re-enable after fixing). (f) Client using **IPv6** — test **`curl -4`** or add IPv6 allow.

### VM Won't Start

**Problem**: VMs fail to start

**Diagnostics**:
```bash
# Check VM configuration
qm config VMID

# Check VM logs
journalctl -u qemu-server@VMID

# Check storage
qm list
pvesm status
```

**Solution**:
```bash
# Start VM manually
qm start VMID

# Reset VM if corrupted
qm reset VMID

# Check hardware settings
qm set VMID --memory 4096 --cores 2
```

### Cloud-Init Issues

**Problem**: Cloud-init configuration not applying

**Diagnostics**:
```bash
# Check cloud-init status in VM
cloud-init status

# View cloud-init logs
journalctl -u cloud-init

# Check user-data
cat /var/lib/cloud/instance/user-data.txt
```

**Solution**:
```bash
# Regenerate cloud-init
qm set VMID --cicustom user=local:snippets/user-data.yml

# Clean cloud-init cache
cloud-init clean

# Force cloud-init run
cloud-init init --local
```

## 🔥 OPNsense Configuration Issues

### Can't Access OPNsense Web Interface

**Problem**: Unable to connect to OPNsense web UI

**Diagnostics**:
```bash
# Check if VM is running
qm status VMID

# Check network connectivity
ping opnsense-ip

# Check if web interface is listening
nmap -p 80,443 opnsense-ip
```

**Solution**:
```bash
# Access via console
qm terminal VMID

# Reset web interface
# In OPNsense console: Option 12 -> Reset web interface

# Check firewall rules
# In OPNsense: Firewall -> Rules -> LAN
```

### Firewall Rules Not Working

**Problem**: Traffic not being blocked/allowed as expected

**Diagnostics**:
```bash
# Check firewall logs
tail -f /var/log/filter.log

# Test connectivity
nc -zv target-ip target-port

# Check rule order
# In OPNsense GUI: Firewall -> Rules
```

**Solution**:
1. Verify rule order (rules are processed top to bottom)
2. Check source/destination specifications
3. Ensure interfaces are correct
4. Clear firewall states: Diagnostics -> States -> Reset States

### DHCP Server Issues

**Problem**: DHCP not assigning addresses

**Diagnostics**:
```bash
# Check DHCP service
service dhcpd status

# Check DHCP configuration
cat /var/dhcpd/etc/dhcpd.conf

# Monitor DHCP logs
tail -f /var/log/dhcpd.log
```

**Solution**:
```bash
# Restart DHCP service
service dhcpd restart

# Check IP pool availability
# In OPNsense: Services -> DHCPv4 -> [Interface]

# Clear DHCP leases
# Services -> DHCPv4 -> Leases -> Clear all
```

## 🔐 VPN and Security Issues

### Tailscale Connection Problems

**Problem**: Tailscale VPN not connecting

**Diagnostics**:
```bash
# Check Tailscale status
tailscale status

# Check Tailscale logs
journalctl -u tailscaled

# Test connectivity
tailscale ping peer-name
```

**Solution**:
```bash
# Re-authenticate
tailscale up --reset

# Check firewall rules for UDP 41641
iptables -L | grep 41641

# Restart Tailscale
systemctl restart tailscaled
```

### Suricata Not Detecting Threats

**Problem**: IDS/IPS not generating alerts

**Diagnostics**:
```bash
# Check Suricata status
systemctl status suricata

# Check rule updates
suricata-update list-enabled-sources

# Test rule detection
curl http://testmyids.com
```

**Solution**:
```bash
# Update rules
suricata-update

# Restart Suricata
systemctl restart suricata

# Check configuration
suricata -T -c /etc/suricata/suricata.yaml
```

### Certificate Issues

**Problem**: SSL/TLS certificate errors

**Diagnostics**:
```bash
# Check certificate validity
openssl x509 -in cert.pem -text -noout

# Test SSL connection
openssl s_client -connect hostname:443

# Check certificate chain
curl -I https://hostname
```

**Solution**:
```bash
# Regenerate certificates
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365

# Update certificate in OPNsense
# System -> Trust -> Certificates -> Add

# Restart web service
service nginx restart
```

## 💾 Backup and Storage Issues

### Backup Failures

**Problem**: Proxmox backups failing

**Diagnostics**:
```bash
# Check backup storage
pvesm status

# Check backup logs
journalctl -u pve-daily-update

# List backups
pvesh get /nodes/NODE/storage/STORAGE/content --content backup
```

**Solution**:
```bash
# Clean old backups
vzdump --cleanup 1

# Check storage permissions
ls -la /var/lib/vz/dump/

# Test backup manually
vzdump VMID --storage local --compress gzip
```

### Storage Full

**Problem**: Storage space exhausted

**Diagnostics**:
```bash
# Check disk usage
df -h
pvesm status

# Find large files
du -sh /* | sort -hr | head -10

# Check VM disk usage
qm list
```

**Solution**:
```bash
# Clean old backups
find /var/lib/vz/dump/ -mtime +7 -delete

# Remove unused VM disks
qm disk unlink VMID virtio0

# Add storage
pvesm add dir NEW-STORAGE --path /mnt/storage
```

## 🧪 Testing and Validation Issues

### Test Suite Failures

**Problem**: Integration tests failing

**Diagnostics**:
```bash
# Run tests with verbose output
cd docker-test-framework
./run-integration-tests.sh -t example -v

# Check Docker status
docker ps -a
docker logs container-name
```

**Solution**:
```bash
# Clean Docker environment
docker system prune -a

# Rebuild test environment
docker-compose down
docker-compose up --build

# Check test configuration
cat docker-test-framework/example-site.yml
```

### Configuration Validation Errors

**Problem**: `validate-config.sh` reports errors

**Common Issues**:

1. **YAML Syntax Errors**:
   ```bash
   # Check YAML syntax
   yamllint config/sites/site.yml
   
   # Fix common issues: indentation, missing quotes
   ```

2. **Missing Required Fields**:
   ```bash
   # Check required configuration
   grep -r "required" config/
   
   # Add missing fields to site configuration
   ```

3. **Invalid Network Configuration**:
   ```bash
   # Validate network ranges
   ipcalc 10.1.0.0/16
   
   # Check for conflicts
   grep -r "10.1" config/
   ```

## 📞 Getting Additional Help

### Log Collection

When reporting issues, collect relevant logs:

```bash
# Create support bundle
mkdir support-logs
cp /var/log/syslog support-logs/
cp ~/.ansible.log support-logs/ 2>/dev/null
journalctl -u pveproxy > support-logs/pveproxy.log
tar czf support-$(date +%Y%m%d).tar.gz support-logs/
```

### System Information

Include system details:

```bash
# System info
uname -a
lsb_release -a
free -m
df -h

# Network info
ip addr show
ip route show

# Service status
systemctl status pveproxy pvedaemon pve-cluster
```

### LXC snippet playbook (Ansible) fails mid-run

During **lab / nested-router** builds, OPNsense may not forward **public DNS** or **HTTPS** until **WAN** and **NAT** are correct. The playbook can still **push snippets** and apply **`write_files`** without running **`runcmd`** (Pi-hole **`curl`**, **`apt`**):

```bash
ansible-playbook workloads/ansible/playbooks/lxc-apply-cloud-init-snippets.yml \
  -e lxc_skip_dns_preflight=true \
  -e lxc_skip_cloud_init_install=true \
  -e lxc_skip_cloud_init_final=true
```

Re-run **without** those **`-e`** flags when **WAN**, **DNS**, and **outbound HTTPS** work end-to-end from the CTs.

**`lxc_skip_cloud_init_install=true`** only works if the **`cloud-init`** package is **already installed** in each LXC (e.g. baked into the template). Otherwise run **without** that flag once so **`apt`** can install **`cloud-init`** (needs working DNS to Debian mirrors).

**No network and no `cloud-init` in the guest:** use **`-e lxc_seed_nocloud_only=true`** together with the other skips so the playbook **only writes** **`meta-data`** and **`user-data`** under **`/var/lib/cloud/seed/nocloud/`** — then install **`cloud-init`** when the CT can reach Debian mirrors and re-run the playbook without **`lxc_seed_nocloud_only`**.

### LXC: `Destination Host Unreachable` to the default gateway (`ping 192.168.0.1`)

**Symptoms:** Inside the CT, **`ping 192.168.0.1`** and **`ping 1.1.1.1`** return **Destination Host Unreachable** (often “From 192.168.0.x …”), not just DNS failure.

**Meaning:** This is **layer 2 / switching / VLAN**, not **`resolv.conf`**. The stack cannot reach the **next hop** on the wire—usually **no ARP reply** from the gateway because the CT’s **veth is not on the same Ethernet broadcast domain** as **`192.168.0.1`**, or the **gateway IP is wrong** for that segment.

**Check:**

1. On **Proxmox** (host): **`ping 192.168.0.1`** — if the **host** reaches the router but the **CT** does not, fix the **CT’s bridge and VLAN** in the UI / Terraform (**`network_interface`**, **`vlan_id`**, **`vmbr`**).
2. **VLAN mismatch:** If the CT has **`192.168.0.201/24`** but **`vlan_id`** (e.g. **50**) tags it onto a trunk where **192.168.0.0/24** is **not** that VLAN, the router will never answer ARP. For an **untagged** home LAN, the CT must be on the **native VLAN** of the bridge that faces the router (often **`vlan_id` unset / 0** — confirm in **`bpg/proxmox`** docs for your version).
3. Inside the CT: **`ip neigh`** — **`192.168.0.1`** stuck **FAILED** / **INCOMPLETE** confirms neighbor discovery failure.
4. **Cable / bridge:** Ensure the **physical NIC** backing **`vmbr`** actually goes to the same switch / port / VLAN as the ISP router’s LAN.

DNS errors (**`Temporary failure in name resolution`**) are a **consequence** until L3 to the gateway works.

### LXC: `dig @1.1.1.1` times out (even with `nameserver 1.1.1.1` in `resolv.conf`)

If **`dig @1.1.1.1`** from inside the CT **times out** and **`curl https://deb.debian.org`** fails, the CT **has no usable path to the public internet** through its **default gateway** — this is **not** solved by editing **`resolv.conf`** again.

Check in order:

1. **`ping <default-gateway>`** from inside the CT (e.g. **`192.168.0.1`**) — must work for L3 to the router. If it fails, fix **bridge / VLAN / CT IP** on Proxmox.
2. **Home router** — **client isolation**, **parental controls**, **“force ISP DNS”** / block **UDP/TCP 53** to **1.1.1.1** / **8.8.8.8**, or **no NAT** from LAN to WAN for those clients.
3. **Proxmox host firewall** — **`iptables -L FORWARD -n -v`** / **nftables**: rules that **DROP** traffic from **vmbr** / **CT subnet** toward the WAN. **UFW** “routed” defaults vary; forwarding can be denied.
4. Until fixed, run **`lxc-apply-cloud-init-snippets.yml`** with **`-e lxc_skip_dns_preflight=true`** (and usually skip **`cloud-init install`/`final`** until outbound works).

### “Proxmox reaches the internet but LXCs still cannot resolve `deb.debian.org`” (even with `1.1.1.1`)

The **Proxmox host** and **each LXC** have **separate** IP addresses and **default gateways**. Default **`workloads/terraform/main.tf`** puts service LXCs on **`192.168.5.0/24`** with gateway **`192.168.5.1`** (OPNsense). **All** traffic from the CT — including **UDP/TCP 53** to **`1.1.1.1`** — is routed **via `192.168.5.1`**. Changing **`/etc/resolv.conf`** (Ansible) only picks the **resolver address**; it does **not** remove OPNsense from the path. If OPNsense **blocks**, **redirects**, or **cannot reach** the internet for DNS, resolution fails.

To use **only the ISP router** (`192.168.0.1`) for CT **gateway + DNS**, change **Terraform** so each LXC’s **IPv4 + gateway** live on that subnet (see **“Flat LAN bootstrap”** in **`workloads/terraform/README.md`**), then **`terraform apply`** and re-run the playbook.

### LXC playbook: `Permission denied (publickey)` or wrong IP

Ansible connects to **Proxmox** over **SSH** using **`proxmox/ansible/inventory/hosts.yaml`** (`ansible_host`, **`ansible_user`**). This error means the host was reached but **no SSH key matched** for that user — it is **not** a cloud-init or CT DNS problem.

1. **DHCP changed the node IP** — update **`ansible_host`** to the current address (or use a **DHCP reservation** / **static IP** on the router so the address stops moving).
2. **User `ansible` must accept your key** — on the Proxmox node, `~ansible/.ssh/authorized_keys` must include the public key for the identity you use from your workstation. From the machine that runs Ansible: **`ssh-copy-id ansible@<proxmox-ip>`** (after creating the `ansible` user and sudo access if you follow that pattern), **or** set **`ansible_user: root`** in inventory if you only use **root** + key (less ideal but common on lab nodes).

3. **`ssh fw` works but Ansible says Permission denied** — Ansible connects to **`ansible@<ansible_host>`** (the **IP**). Your **`~/.ssh/config`** may only set **`IdentityFile`** under **`Host fw`** or an old IP alias, not under **`Host <current-ip>`**, so the SSH client falls back to other keys. Fix: add a **`Host <proxmox-ip>`** block with the same **`IdentityFile`**, **or** set **`ansible_ssh_private_key_file`** in **`proxmox/ansible/inventory/host_vars/pve-firewall.yml`** (see the example there matching **`workloads/terraform/providers.tf`**).

Confirm with **`ssh -v ansible@<ip>`** (or **`root@<ip>`**) before re-running the playbook.

### Omada AP / OPT2: no internet

**Symptoms:** Wi-Fi clients or the **Omada** controller/AP segment on **OPT2** (or a **Wi-Fi VLAN**) cannot reach the internet even when **LAN** can.

**Check on OPNsense:**

1. **Outbound NAT** — **Firewall → NAT → Outbound**: the **source** for OPT2’s subnet must be **NAT’d to WAN**. Default “automatic” rules sometimes only cover **LAN**; use **hybrid** or **manual** and add a rule for **OPT2 net → WAN** if needed.
2. **Firewall rules** — **Firewall → Rules → OPT2** (or the interface where APs sit): **allow IPv4** from that net to **WAN** (or **any**), **above** any **block** or **reject** rules. Same for **UDP/TCP 53** if clients use **OPNsense** or **Pi-hole** for DNS.
3. **Gateways / DHCP** — Clients must get a **default gateway** and **DNS** that match your design (often **OPNsense’s address on that segment**, not an upstream router, unless you intentionally bypass the firewall).
4. **Nested lab** — If **OPNsense WAN** and **LAN** are both on the **same upstream LAN** (e.g. both DHCP from the **original router**), verify **no IP/subnet overlap** between **WAN**, **LAN**, and **OPT2**, and that you are not expecting **hairpin** or **asymmetric** paths without explicit rules.

### Community Support

- **GitHub Issues**: For bugs and feature requests
- **GitHub Discussions**: For questions and community help
- **Documentation**: Check all files in `docs/` directory
- **Examples**: Review `docker-test-framework/example-*` configs

---

If you can't find a solution here, please create a GitHub issue with:
1. Problem description
2. Steps to reproduce
3. Expected vs actual behavior
4. System information
5. Relevant logs 
