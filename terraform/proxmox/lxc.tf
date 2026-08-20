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

# Whisper node on pve3. Transcription is CPU-bound and was competing with the LLM
# for pve2, which is the only host with DDR5 and therefore the only sensible place
# to run inference. Splitting the two lets a lecture transcribe here while the
# previous one is summarised on pve2, and leaves pve2's cores and RAM to the model.
#
# pve3 also runs k3s-cp-03 (etcd), which is latency-sensitive, so this container is
# given a low CPU weight rather than few cores: it uses whatever is idle but yields
# immediately under contention.
resource "proxmox_virtual_environment_container" "whisper" {
  node_name = "pve3"
  vm_id     = 202

  unprivileged = true

  features {
    nesting = true
  }

  initialization {
    hostname = "whisper"

    dns {
      servers = ["1.1.1.1", "8.8.8.8"]
    }

    ip_config {
      ipv4 {
        address = "192.168.10.42/24"
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
    # large-v3 model cache (~6 GB) + docker images + room for a second model.
    size = 40
  }

  cpu {
    cores = 8
    # PVE cgroup v2 default is 100. Deprioritised against cp-03's etcd.
    units = 20
  }

  memory {
    dedicated = 8192
  }

  lifecycle {
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
    # 180 GB: llama3.3:70b (~42 GB) and qwen3.6:35b-a3b (~22 GB) are kept side by
    # side while their speed and output quality are compared, plus Open WebUI and
    # its RAG store. vmdata has ~1.2 TB free.
    size = 180
  }

  cpu {
    cores = 6
  }

  # 52 GB cap so a large overnight model fits. It's a cap, not a reservation —
  # Ollama unloads at idle (keep_alive=0) so daytime usage stays low.
  #
  # pve2 RAM budget (62 GB usable): cp-02 6 + worker-02 6 + arr-stack 6 + ai-lab 52
  # = 70 GB of caps. That is deliberate overcommit, valid only because arr-stack
  # rarely reaches its cap and ai-lab holds RAM only while a model is loaded.
  # LIA VM 105 (central-01) is powered off permanently as of 2026-08-20, which is
  # what makes the remaining overcommit survivable. If a run ever OOMs the host,
  # shrink this cap first — cp-02 runs etcd and must not be the one that loses.
  memory {
    dedicated = 53248
  }

  lifecycle {
    ignore_changes = [initialization, operating_system]
  }
}
