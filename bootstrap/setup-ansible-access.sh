#!/bin/bash
set -euo pipefail

echo "=== Proxmox Bootstrap: Ansible User + Clean Repos ==="

# Install sudo if missing
if ! command -v sudo >/dev/null 2>&1; then
    apt update || true
    apt install -y sudo ufw fail2ban unattended-upgrades
fi

# Create ansible user with passwordless sudo
if ! id ansible >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" ansible
    echo "ansible ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/ansible
    chmod 0440 /etc/sudoers.d/ansible
fi

# Setup SSH key (replace with your actual public key from WSL)
mkdir -p /home/ansible/.ssh
cat << 'EOF' > /home/ansible/.ssh/authorized_keys
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHjyv6zKkkXzgpbA+eCwEHsv1GecZGic979egEiTLdyN chris@fyberlabs.com
EOF
chown -R ansible:ansible /home/ansible/.ssh
chmod 700 /home/ansible/.ssh
chmod 600 /home/ansible/.ssh/authorized_keys

echo "Ansible user ready. You can now run playbooks with --user ansible -b"
