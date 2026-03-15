terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.50.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  # TODO: Set insecure = false and configure cacert for proper TLS verification.
  # Download Proxmox CA cert: ssh root@proxmox cat /etc/pve/pve-root-ca.pem > ~/.config/proxmox/pve-root-ca.pem
  # Then add: cacert = file("~/.config/proxmox/pve-root-ca.pem")
  insecure = true
}
