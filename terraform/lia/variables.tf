variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "Proxmox API token ID"
  type        = string
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key for cloud-init"
  type        = string
}

variable "template_id" {
  description = "AlmaLinux cloud-init template VM ID"
  type        = number
  default     = 9001
}

variable "template_node" {
  description = "Proxmox node where the AlmaLinux template lives (source for cross-node clones)"
  type        = string
  default     = "pve1"
}

variable "vm_datastore" {
  description = "Proxmox storage for VM disks (unified lvmthin pool on the data NVMe of each node)"
  type        = string
  default     = "vmdata"
}

variable "vms" {
  description = "LIA lab VM definitions (name -> {ip, node_name, cores, memory (MB), disk (GB), template_id?, username?, disk_interface?})"
  type = map(object({
    ip          = string
    node_name   = string
    cores       = number
    memory      = number
    disk        = number
    template_id = optional(number)
    username    = optional(string)
    # Must match the boot disk interface of the template being cloned
    # (AlmaLinux template = virtio0, Ubuntu cloud image template = scsi0);
    # otherwise the size applies to a second, unused disk.
    disk_interface = optional(string)
  }))
}
