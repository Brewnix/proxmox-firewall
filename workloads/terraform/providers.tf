terraform {
  required_version = ">= 1.13.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.100" # latest stable as of 2026
    }
  }
}

provider "proxmox" {
  endpoint  = "https://192.168.0.86:8006/" # your N305 IP
  api_token = var.proxmox_api_token        # format: "user@pam!tokenid=secretvalue"
  insecure  = true                         # set false once you have proper cert

  # Optional: SSH agent for template cloning if needed
  ssh {
    agent       = true
    username    = "ansible"
    private_key = file("~/.ssh/id_ed25519_home")
  }
}
