resource "proxmox_virtual_environment_vm" "k3s_control_plane" {
  for_each = var.control_planes

  name      = each.key
  node_name = each.value.node_name

  agent {
    enabled = false
  }

  clone {
    vm_id     = each.value.template_id
    node_name = var.template_node
    full      = true
  }

  cpu {
    cores = var.cp_cores
    # Provider default is qemu64, which hides SSE4.2/x86-64-v2 — numpy 2.x
    # and pyarrow wheels refuse to start on such vCPUs.
    type = "host"
  }

  memory {
    dedicated = var.cp_memory
  }

  disk {
    datastore_id = var.vm_datastore
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
    ignore_changes = [initialization, clone]
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
    vm_id     = each.value.template_id
    node_name = var.template_node
    full      = true
  }

  cpu {
    cores = var.worker_cores
    type  = "host"
  }

  memory {
    dedicated = var.worker_memory
  }

  disk {
    datastore_id = var.vm_datastore
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
    ignore_changes = [initialization, clone]
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
    vm_id = each.value.template_id
  }

  cpu {
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

  # Optional second disk for service VMs that need dedicated data storage
  # (e.g. the PBS datastore). Only created when datastore_disk is set.
  dynamic "disk" {
    for_each = each.value.datastore_disk != null ? [each.value.datastore_disk] : []
    content {
      datastore_id = var.vm_datastore
      interface    = "virtio1"
      size         = disk.value
    }
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
    datastore_id = var.vm_datastore
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
