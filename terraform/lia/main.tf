resource "proxmox_virtual_environment_vm" "lia" {
  for_each = var.vms

  name      = each.key
  node_name = each.value.node_name

  agent {
    enabled = false
  }

  clone {
    vm_id     = var.template_id
    node_name = var.template_node
    full      = true
  }

  cpu {
    # AlmaLinux 9 / RHEL 9 userspace requires x86-64-v2; the Proxmox default
    # kvm64 (v1) makes systemd SIGILL and panics init at boot. "host" passes
    # the node CPU straight through (Intel i5-11500T / Ultra5 are v2+).
    type  = "host"
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.vm_datastore
    interface    = "virtio0"
    size         = each.value.disk
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    dns {
      servers = ["1.1.1.1", "8.8.8.8"]
    }

    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = "192.168.10.1"
      }
    }

    user_account {
      username = "almalinux"
      keys     = [file(pathexpand(var.ssh_public_key_path))]
    }
  }

  lifecycle {
    ignore_changes = [initialization, clone]
  }
}
