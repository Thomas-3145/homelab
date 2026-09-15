terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # Pinned to the minor version this directory has actually been planned and
      # applied against. It was ">= 0.50.0" with the lock file gitignored, so a
      # fresh clone resolved to whatever was newest that day — which is how this
      # directory ended up on 0.95 while terraform/lia sits on 0.111 from the
      # same constraint. The lock file is committed now; upgrading is a
      # deliberate `terraform init -upgrade` plus a reviewed plan, not a side
      # effect of cloning.
      version = "~> 0.95.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"

  # Verification is off because the certificate cannot currently satisfy it, not
  # merely because nobody got around to it. Checked 2026-09-15 on pve1:
  #
  #   subject=CN=pve1.taild78f1d.ts.net
  #   SAN: IP:127.0.0.1, IP:::1, DNS:localhost, IP:192.168.10.10, DNS:pve1,
  #        DNS:pve1.taild78f1d.ts.net
  #
  # The endpoint is 192.168.10.11. The SAN still carries 192.168.10.10 from
  # before the node was renumbered, so a CA file alone would not help — the
  # handshake fails on the name, not on trust. Fixing it means one of:
  #
  #   a) re-issue the node certificates with the current address
  #      (`pvecm updatecerts --force` on each node after correcting the address),
  #      then set cacert = file("~/.config/proxmox/pve-root-ca.pem")
  #   b) point the endpoint at a name that is in the SAN — DNS:pve1 resolves to
  #      the Tailscale address here, not to 192.168.10.11, so this needs a hosts
  #      entry or a split-horizon record first
  #
  # Both touch live infrastructure, so they are deliberately not done here.
  insecure = true
}
