resource "proxmox_virtual_environment_vm" "k3s_control_plane" {
  for_each = var.control_planes

  name      = each.key
  node_name = each.value.node_name

  # Lets Proxmox freeze the guest filesystem before a vzdump snapshot, so PBS
  # backups are filesystem-consistent instead of crash-consistent. Requires
  # qemu-guest-agent inside the guest (installed by the common role) and a
  # power-cycle — the virtio-serial device is only added at machine start.
  agent {
    enabled = true
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

  # Lets Proxmox freeze the guest filesystem before a vzdump snapshot, so PBS
  # backups are filesystem-consistent instead of crash-consistent. Requires
  # qemu-guest-agent inside the guest (installed by the common role) and a
  # power-cycle — the virtio-serial device is only added at machine start.
  agent {
    enabled = true
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

  # Lets Proxmox freeze the guest filesystem before a vzdump snapshot, so PBS
  # backups are filesystem-consistent instead of crash-consistent. Requires
  # qemu-guest-agent inside the guest (installed by the common role) and a
  # power-cycle — the virtio-serial device is only added at machine start.
  agent {
    enabled = true
  }

  clone {
    # Explicit node_name, like the control plane and worker resources. Without it
    # the clone only works while the template happens to live on the same node as
    # the target VM — the Debian 13 template (9002) is on pve1, so moving a
    # service VM to pve2 or pve3 would break apply.
    node_name = var.template_node
    vm_id     = each.value.template_id
  }

  cpu {
    cores = each.value.cores
    # Matches the control plane and workers. The default (qemu64) hides SSE4.2
    # and AES-NI from the guest, which measurably slows PBS's checksumming.
    type = "host"
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
    # Without this, cloud-init inherits the Proxmox host's resolver. Every node
    # runs Tailscale, so that resolver is MagicDNS (100.100.100.100) — which a
    # fresh guest cannot reach until Tailscale is up, and Tailscale is installed
    # by the common role, which needs working DNS to fetch packages. Pin public
    # resolvers so the guest can bootstrap. Same as the LXCs in lxc.tf.
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
      username = "ubuntu"
      keys     = [file(pathexpand(var.ssh_public_key_path))]
    }
  }

  # Same exemption the control plane and workers already carry, and for the same
  # reason: Proxmox stores the cloud-init SSH key URL-encoded, so it reads back
  # with a trailing %0A that never matches the file on disk. Without this the
  # services resource had a permanent one-line diff, which meant `terraform plan`
  # was never clean — and a plan that is never clean cannot be used to spot real
  # drift, because the real drift drowns in the noise.
  lifecycle {
    ignore_changes = [initialization, clone]
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

  # Lets Proxmox freeze the guest filesystem before a vzdump snapshot, so PBS
  # backups are filesystem-consistent instead of crash-consistent. Requires
  # qemu-guest-agent inside the guest (installed by the common role) and a
  # power-cycle — the virtio-serial device is only added at machine start.
  agent {
    enabled = true
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
