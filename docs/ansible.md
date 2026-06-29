# Ansible

Ansible handles everything between Terraform provisioning and k3s being ready — node configuration, hardening, and cluster installation.

## Role structure

| Role | Applied to | Purpose |
|---|---|---|
| `common` | All VMs | DNS, SSH hardening (port 22456, no password auth), fail2ban, unattended-upgrades, Tailscale |
| `k3s_node` | Control plane + workers | Kernel modules, sysctl tuning, Longhorn dependencies |
| `node_exporter` | All nodes + physical hosts | Prometheus metrics exporter |
| `proxmox` | pve1, pve3 | Host-level hardening (NIC fixes, kernel pins) |

The `common` role runs on every managed host. Roles are composable — a k3s node gets `common` + `k3s_node` + `node_exporter`, a service VM only gets `common`.

## Inventory

Hosts are organized into groups that reflect their actual role:

```
proxmox_vms/
├── k3s_control_plane/
│   ├── k3s_init        # Bootstraps cluster with --cluster-init
│   └── k3s_servers     # Join via token from init node
├── k3s_workers
└── services            # Non-k3s VMs (arr-stack etc.)
physical_hosts/         # pve1, pve3, 3145 — managed separately
```

## Secrets

Sensitive values (Tailscale auth key, etc.) are stored as SOPS-encrypted vault files in `ansible/inventory/group_vars/` and decrypted at runtime via the `community.sops` collection.
