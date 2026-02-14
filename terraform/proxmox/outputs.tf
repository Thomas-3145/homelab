output "control_plane_ips" {
  description = "IP addresses of k3s control plane nodes"
  value = [for vm in proxmox_virtual_environment_vm.k3s_control_plane :
    vm.initialization[0].ip_config[0].ipv4[0].address
  ]
}

output "control_plane_names" {
  description = "Hostnames of k3s control plane nodes"
  value       = proxmox_virtual_environment_vm.k3s_control_plane[*].name
}

output "control_plane_ids" {
  description = "Proxmox VM IDs of control plane nodes"
  value       = proxmox_virtual_environment_vm.k3s_control_plane[*].vm_id
}
