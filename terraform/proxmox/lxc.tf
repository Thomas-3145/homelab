resource "proxmox_virtual_environment_container" "arr_stack" {
  node_name = "pve3"
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
    ignore_changes = [initialization]
  }
}
