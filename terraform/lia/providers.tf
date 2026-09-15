terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # Pinned to the version this directory is actually on. Note that it differs
      # from terraform/proxmox (~> 0.95.0): both carried ">= 0.50.0" with the lock
      # file gitignored, so each resolved to whatever was current when it was last
      # initialised, and they drifted 16 minor versions apart. Pinning freezes
      # that split deliberately instead of leaving it to chance — converging the
      # two is a separate, reviewed upgrade, not something a clone should do.
      version = "~> 0.111.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  # Verification is off because the node certificate's SAN does not cover the
  # endpoint address — see the long note in terraform/proxmox/providers.tf for
  # what was checked and what fixing it actually requires.
  insecure = true
}
