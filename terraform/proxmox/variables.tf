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
  description = "Default cloud-init template VM ID"
  type        = number
}

variable "template_node" {
  description = "Proxmox node where the cloud-init template lives (source for cross-node clones)"
  type        = string
  default     = "pve1"
}

variable "vm_datastore" {
  description = "Proxmox storage for VM disks (unified lvmthin pool on the data NVMe of each node)"
  type        = string
  default     = "vmdata"
}

variable "control_planes" {
  description = "k3s control plane VM definitions (name -> {ip, node_name, template_id})"
  type = map(object({
    ip          = string
    node_name   = string
    template_id = number
  }))
}

variable "cp_cores" {
  description = "CPU cores for control plane nodes"
  type        = number
}

variable "cp_memory" {
  description = "RAM in MB for control plane nodes"
  type        = number
}

variable "cp_disk" {
  description = "Disk size in GB for control plane nodes"
  type        = number
}

variable "workers" {
  description = "k3s worker node VM definitions (name -> {ip, node_name, template_id})"
  type = map(object({
    ip          = string
    node_name   = string
    template_id = number
  }))
}

variable "worker_cores" {
  description = "CPU cores for worker nodes"
  type        = number
}

variable "worker_memory" {
  description = "RAM in MB for worker nodes"
  type        = number
}

variable "worker_disk" {
  description = "Disk size in GB for worker nodes"
  type        = number
}

variable "service_vms" {
  description = "Permanent service VMs running standalone workloads (e.g. arr-stack)"
  type = map(object({
    ip          = string
    node_name   = string
    cores       = number
    memory      = number
    disk        = number
    template_id = number
  }))
  default = {}
}

variable "test_vms" {
  description = "Ad-hoc lab VMs (name -> {ip, node_name, cores, memory, disk})"
  type = map(object({
    ip        = string
    node_name = string
    cores     = number
    memory    = number
    disk      = number
  }))
  default = {}
}
