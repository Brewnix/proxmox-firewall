# Proxmox node Terraform (optional)

This directory is reserved for **hypervisor-only** Terraform (`bpg/proxmox`): API roles, storage bindings, or other **node** resources that must **not** live in [workloads/terraform](../../workloads/terraform/) (guest VMs/LXCs).

Greenfield automation today is **Ansible-first** for the host — see [proxmox/ansible/](../ansible/).

## Remote state

Copy [backend.tf.example](backend.tf.example) to `backend.tf`, set the backend for your team (S3, Terraform Cloud, etc.), and run `terraform init -migrate-state` when switching from local state.
