output "control_plane_ips" {
  value = {
    for k, v in proxmox_virtual_environment_vm.k3s_control_plane :
    k => v.initialization[0].ip_config[0].ipv4[0].address
  }
}

output "control_plane_names" {
  value = keys(proxmox_virtual_environment_vm.k3s_control_plane)
}

output "control_plane_ids" {
  value = {
    for k, v in proxmox_virtual_environment_vm.k3s_control_plane :
    k => v.vm_id
  }
}

output "worker_ips" {
  value = {
    for k, v in proxmox_virtual_environment_vm.k3s_workers :
    k => v.initialization[0].ip_config[0].ipv4[0].address
  }
}

output "worker_names" {
  value = keys(proxmox_virtual_environment_vm.k3s_workers)
}

output "worker_ids" {
  value = {
    for k, v in proxmox_virtual_environment_vm.k3s_workers :
    k => v.vm_id
  }
}
