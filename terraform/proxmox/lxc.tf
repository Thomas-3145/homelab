resource "proxmox_virtual_environment_container" "arr_stack" {
  node_name = "pve2"
  vm_id     = 200

  unprivileged = true

  features {
    nesting = true
  }

  initialization {
    hostname = "arr-stack"

    dns {
      servers = ["1.1.1.1", "8.8.8.8"]
    }

    ip_config {
      ipv4 {
        address = "192.168.10.40/24"
        gateway = "192.168.10.1"
      }
    }

    user_account {
      keys = [file(pathexpand(var.ssh_public_key_path))]
    }
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  operating_system {
    template_file_id = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
    type             = "ubuntu"
  }

  disk {
    datastore_id = var.vm_datastore
    size         = 32
  }

  mount_point {
    path   = "/mnt/media"
    volume = var.vm_datastore
    size   = "500G"
  }

  cpu {
    cores = 4
  }

  memory {
    dedicated = 6144
  }

  lifecycle {
    # template_file_id is only used at creation and can't be read back after an
    # import, so it would otherwise force replacement of the live container.
    ignore_changes = [initialization, operating_system]
  }
}

# AI lab: local Whisper large-v3 (lecture/YouTube transcription) and, later,
# Ollama + Open WebUI for LLM summaries. Kept separate from the arr-stack LXC so
# AI experiments don't touch the media services; shares the Arc iGPU via /dev/dri.
resource "proxmox_virtual_environment_container" "ai_lab" {
  node_name = "pve2"
  vm_id     = 201

  unprivileged = true

  features {
    nesting = true
  }

  initialization {
    hostname = "ai-lab"

    dns {
      servers = ["1.1.1.1", "8.8.8.8"]
    }

    ip_config {
      ipv4 {
        address = "192.168.10.41/24"
        gateway = "192.168.10.1"
      }
    }

    user_account {
      keys = [file(pathexpand(var.ssh_public_key_path))]
    }
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  operating_system {
    template_file_id = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
    type             = "ubuntu"
  }

  disk {
    datastore_id = var.vm_datastore
    # 120 GB: the 70B model (~42 GB) + Whisper cache (~6 GB) + images + room for a
    # second model. vmdata has ~1.7 TB free.
    size = 120
  }

  cpu {
    cores = 6
  }

  # 52 GB cap so an overnight Llama 3.3 70B (q4, ~45 GB) fits. It's a cap, not a
  # reservation — daytime usage (Whisper only) stays low. 70B runs require the LIA
  # VM (105) to be off so pve2's 62 GB total isn't exceeded alongside k3s.
  memory {
    dedicated = 53248
  }

  lifecycle {
    ignore_changes = [initialization, operating_system]
  }
}
