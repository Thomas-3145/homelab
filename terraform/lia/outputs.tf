output "vm_ips" {
  value = {
    for k, v in proxmox_virtual_environment_vm.lia :
    k => v.initialization[0].ip_config[0].ipv4[0].address
  }
}

output "vm_ids" {
  value = {
    for k, v in proxmox_virtual_environment_vm.lia :
    k => v.vm_id
  }
}
