resource "proxmox_virtual_environment_vm" "k3s_control_plane" {
  for_each = var.control_planes

  name      = each.key
  node_name = each.value.node_name

  agent {
    enabled = false
  }

  clone {
    vm_id = each.value.template_id
  }

  cpu {
    cores = var.cp_cores
  }

  memory {
    dedicated = var.cp_memory
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "virtio0"
    size         = var.cp_disk
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = "192.168.10.1"
      }
    }

    user_account {
      username = "ubuntu"
      keys     = [file(pathexpand(var.ssh_public_key_path))]
    }
  }

  lifecycle {
    ignore_changes = [initialization]
  }

  provisioner "local-exec" {
    when    = destroy
    command = "IP='${self.initialization[0].ip_config[0].ipv4[0].address}'; ssh -p 22456 -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i ~/.ssh/id_rsa_4096 ubuntu@$${IP%%/*} 'sudo tailscale logout' || true"
  }
}



resource "proxmox_virtual_environment_vm" "k3s_workers" {
  for_each = var.workers

  name      = each.key
  node_name = each.value.node_name

  agent {
    enabled = false
  }

  clone {
    vm_id = each.value.template_id
  }

  cpu {
    cores = var.worker_cores
  }

  memory {
    dedicated = var.worker_memory
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "virtio0"
    size         = var.worker_disk
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = "192.168.10.1"
      }
    }

    user_account {
      username = "ubuntu"
      keys     = [file(pathexpand(var.ssh_public_key_path))]
    }
  }

  lifecycle {
    ignore_changes = [initialization]
  }

  provisioner "local-exec" {
    when    = destroy
    command = "IP='${self.initialization[0].ip_config[0].ipv4[0].address}'; ssh -p 22456 -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i ~/.ssh/id_rsa_4096 ubuntu@$${IP%%/*} 'sudo tailscale logout' || true"
  }
}



resource "proxmox_virtual_environment_vm" "services" {
  for_each = var.service_vms

  name      = each.key
  node_name = each.value.node_name

  agent {
    enabled = false
  }

  clone {
    vm_id = var.template_id
  }

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "virtio0"
    size         = each.value.disk
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = "192.168.10.1"
      }
    }

    user_account {
      username = "ubuntu"
      keys     = [file(pathexpand(var.ssh_public_key_path))]
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "IP='${self.initialization[0].ip_config[0].ipv4[0].address}'; ssh -p 22456 -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i ~/.ssh/id_rsa_4096 ubuntu@$${IP%%/*} 'sudo tailscale logout' || true"
  }
}



resource "proxmox_virtual_environment_vm" "test" {
  for_each = var.test_vms

  name      = each.key
  node_name = each.value.node_name

  agent {
    enabled = false
  }

  clone {
    vm_id = var.template_id
  }

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "virtio0"
    size         = each.value.disk
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = "192.168.10.1"
      }
    }

    user_account {
      username = "ubuntu"
      keys     = [file(pathexpand(var.ssh_public_key_path))]
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "IP='${self.initialization[0].ip_config[0].ipv4[0].address}'; ssh -p 22456 -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i ~/.ssh/id_rsa_4096 ubuntu@$${IP%%/*} 'sudo tailscale logout' || true"
  }
}
