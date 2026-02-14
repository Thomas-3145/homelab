resource "proxmox_virtual_environment_vm" "k3s_control_plane" {
  count = 3

  name      = "k3s-cp-0${count.index + 1}"
  node_name = var.target_node

  timeouts {
    create = "30m"
    update = "30m"
    delete = "10m"
  }

  clone {
    vm_id = var.template_id
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 32
  }

  network_device {
    bridge  = "vmbr0"
    vlan_id = 10
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.10.${count.index + 21}/24"
        gateway = "192.168.10.1"
      }
    }

    user_account {
      username = "ubuntu"
      keys     = [var.ssh_public_key]
    }
  }
}
