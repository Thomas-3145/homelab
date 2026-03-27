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
  default     = "~/.ssh/id_rsa_4096.pub"
}

variable "control_planes" {
  description = "k3s control plane VM definitions (name -> {ip, node_name, template_id})"
  type = map(object({
    ip          = string
    node_name   = string
    template_id = number
  }))
  default = {
    "k3s-cp-01" = { ip = "192.168.10.21", node_name = "pve1", template_id = 9000 }
    "k3s-cp-02" = { ip = "192.168.10.22", node_name = "pve2", template_id = 9001 }
    "k3s-cp-03" = { ip = "192.168.10.23", node_name = "pve2", template_id = 9001 }
  }
}

variable "cp_cores" {
  type    = number
  default = 2
}

variable "cp_memory" {
  type    = number
  default = 4096
}

variable "cp_disk" {
  type    = number
  default = 32
}

variable "template_id" {
  description = "Cloud-init template VM ID"
  type        = number
  default     = 9000
}

variable "workers" {
  description = "k3s worker node VM definitions (name -> {ip, node_name, template_id})"
  type = map(object({
    ip          = string
    node_name   = string
    template_id = number
  }))
  default = {
    "k3s-worker-01" = { ip = "192.168.10.52", node_name = "pve1", template_id = 9000 }
    "k3s-worker-02" = { ip = "192.168.10.53", node_name = "pve2", template_id = 9001 }
  }
}

variable "worker_cores" {
  type    = number
  default = 2
}

variable "worker_memory" {
  type    = number
  default = 4096
}

variable "worker_disk" {
  type    = number
  default = 32
}

variable "test_vms" {
  description = "Test VMs to provision"
  type = map(object({
    ip        = string
    node_name = string
    cores     = number
    memory    = number
    disk      = number
  }))
  default = {}
}
