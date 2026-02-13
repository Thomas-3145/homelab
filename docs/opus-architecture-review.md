# Architecture Review & Recommendations

> **Date**: 2026-02-14
> **Reviewer**: Claude Opus 4.6
> **Project**: Thomas's Homelab - K3s Infrastructure
> **Current Phase**: Phase 1 (Terraform) - Complete

---

## Executive Summary

The project has a **solid foundation**: clean repository structure, well-planned 7-phase roadmap, and working Terraform that provisions 3 control plane VMs on Proxmox. Documentation quality is excellent for both human readers and AI assistants.

**Key findings:**
1. **Security** - Good baseline (.gitignore excludes secrets), but Terraform config lacks hardening and the VMs have no firewall or SSH hardening yet
2. **Architecture** - 3 control plane VMs on a single Proxmox host means HA is only at the k3s level, not at the hardware level. This is fine for learning but worth acknowledging
3. **Scalability** - The design scales well to hybrid cloud. Adding the Pi as a worker + future AWS nodes is a natural progression
4. **Gaps** - No Ansible, no k3s, no apps yet. The roadmap covers all of this but execution is at the very beginning

**Overall assessment**: Well-architected for a learning project. The roadmap is realistic and the design decisions are sound. Focus should now shift from planning to execution.

---

## Detailed Analysis

### 1. Terraform (terraform/proxmox/)

#### What's good
- Clean separation: `main.tf`, `providers.tf`, `variables.tf`
- Uses `bpg/proxmox` provider (better maintained than `telmate/proxmox`)
- Secrets properly marked `sensitive = true` in variables
- `.gitignore` correctly excludes `.tfvars`, `.tfstate`, and `.terraform/`
- Cloud-init for automated VM provisioning

#### Issues & Recommendations

**T1. Missing Terraform outputs** (Priority: Medium)
No `outputs.tf` exists. Add one to expose VM IPs, names, and IDs for use in Ansible dynamic inventory or scripts.

```hcl
# terraform/proxmox/outputs.tf
output "control_plane_ips" {
  value = [for vm in proxmox_virtual_environment_vm.k3s_control_plane :
    vm.initialization[0].ip_config[0].ipv4[0].address
  ]
}
```

**T2. No Terraform state backend** (Priority: Medium)
State is local-only (`terraform.tfstate` on disk). If the laptop dies, state is lost.

Options ranked by simplicity:
1. **Git-ignored local file + manual backup** (current - acceptable for now)
2. **Terraform Cloud free tier** (remote state, locking, no cost)
3. **S3 + DynamoDB** (overkill for homelab)

Recommendation: Move to Terraform Cloud when you reach Phase 6 (CI/CD). For now, ensure the state file is backed up.

**T3. No terraform.tfvars.example** (Priority: Low)
Other developers (or future-you after a fresh clone) won't know what variables to set. Create a sanitized example:

```hcl
# terraform/proxmox/terraform.tfvars.example
proxmox_api_url          = "https://192.168.10.20:8006"
proxmox_api_token_id     = "user@pam!token-name"
proxmox_api_token_secret = "change-me"
ssh_public_key           = "ssh-rsa AAAA..."
target_node              = "pve"
template_id              = 9000
```

**T4. VM disk size is 20GB** (Priority: Low)
The roadmap examples show 32GB. 20GB works for k3s control plane but will be tight if Longhorn uses local storage. Consider 32GB for future-proofing.

**T5. No VLAN tag on network** (Priority: Medium)
The `network_device` block uses `bridge = "vmbr0"` but doesn't specify a VLAN tag. If your Proxmox bridge is VLAN-aware, you should add `vlan_id = 10` to ensure traffic stays in the homelab VLAN. Verify this matches your Proxmox network setup.

**T6. SSH key not injected via cloud-init** (Priority: High)
The `user_account` block only sets `username = "ubuntu"` but the `ssh_public_key` variable defined in `variables.tf` is never used in `main.tf`. This means either:
- SSH keys are set via the Proxmox template (fragile), or
- Password auth is used (insecure)

Fix by adding to the `initialization` block:
```hcl
user_account {
  username = "ubuntu"
  keys     = [var.ssh_public_key]
}
```

---

### 2. Security Assessment

#### Current state
- **.gitignore**: Properly excludes secrets, state files, vault passwords - well done
- **Proxmox API**: Uses token auth (not root password) - correct approach
- **TLS**: `insecure = true` for self-signed cert on Proxmox - acceptable for homelab LAN
- **VMs**: No hardening applied yet (no Ansible = no firewall, no fail2ban, no SSH hardening)

#### Recommendations

**S1. Rotate Proxmox API token** (Priority: High - if ever committed)
Verify with `git log -p --all -S "proxmox_api_token"` that the API token was never committed to git history. If it was, rotate it immediately and consider using `git filter-repo` to scrub history.

**S2. Create a dedicated Proxmox API user** (Priority: High)
The roadmap mentions `root@pam!terraform-token`. Using root for API access is overly permissive. Create a dedicated user:

```bash
# On Proxmox
pveum user add terraform@pve
pveum role add TerraformRole -privs "VM.Allocate VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Monitor VM.Audit VM.PowerMgmt Datastore.AllocateSpace Datastore.Audit SDN.Use"
pveum aclmod / -user terraform@pve -role TerraformRole
pveum user token add terraform@pve terraform-token
```

**S3. SSH hardening via Ansible** (Priority: High - Phase 2)
When you write Ansible playbooks, include:
- Disable password authentication
- Disable root login
- Change SSH port (optional, defense-in-depth)
- Install and configure `fail2ban`
- Configure UFW with minimal open ports

**S4. Secrets management strategy** (Priority: Medium - Phase 3)
For Kubernetes secrets, recommended approach for homelab:
1. **Sealed Secrets** - simple, works offline, Git-friendly. Best fit for your setup.
2. External Secrets Operator - overkill without a cloud secrets manager
3. SOPS + age - good alternative, encrypts files in-place

Recommendation: Use **Sealed Secrets** for its simplicity and because it's a great portfolio piece to demonstrate.

---

### 3. Cluster Architecture Analysis

#### Current design: 3 CP VMs on 1 Proxmox host + 1 Pi worker

**Strengths:**
- HA at the k3s level (etcd quorum with 3 nodes)
- Mixed architecture (amd64 + arm64) demonstrates real-world multi-arch
- Resource allocation is reasonable (2 CPU, 4GB RAM per CP node = 6 CPU, 12GB total)

**Weaknesses:**
- All 3 CP nodes on same physical host = single point of failure at hardware level
- Proxmox host failure = complete control plane loss
- 32GB RAM total on HP, with 12GB for CPs + Proxmox overhead leaves ~16GB for Proxmox itself

**Honest assessment**: This is perfectly fine for a homelab learning environment. True HA requires multiple physical hosts, which isn't realistic with current hardware. The architecture still teaches important K8s HA concepts (etcd, leader election, control plane redundancy) even if hardware-level HA isn't achieved.

#### Alternative considered: 2 CP + 1 worker on Proxmox, Pi as worker

This would save 4GB RAM but loses the ability to demonstrate a proper 3-node etcd quorum. The current choice (3 CP) is better for learning and portfolio demonstration.

#### Recommendation for cluster design

Keep the current 3 CP + 1 Pi worker design. When you reach Phase 7 (hybrid cloud), adding an AWS node as a second worker demonstrates real hybrid architecture. The control plane stays local (low latency for etcd), workers are distributed.

```
┌──────────────────────────────────┐
│ Proxmox (192.168.10.20)         │
│  ├── k3s-cp-01 (server)         │
│  ├── k3s-cp-02 (server)         │
│  └── k3s-cp-03 (server)         │
└──────────────────────────────────┘
           │
    k3s cluster join
           │
┌──────────┴──────────┐    ┌──────────────┐
│ Homelab Pi (.10.11) │    │ AWS EC2      │
│ worker (arm64)      │    │ worker (fut.)│
└─────────────────────┘    └──────────────┘
```

---

### 4. Storage Strategy

#### Recommendation: Start simple, evolve later

| Phase | Storage approach | Why |
|-------|-----------------|-----|
| Phase 2-3 | `local-path` (k3s default) | Already included, zero setup, works immediately |
| Phase 4 | Longhorn (2 replicas) | Needed when apps require persistent data that survives node failure |
| Phase 7 | Longhorn + S3 backup | DR to cloud |

**Longhorn considerations with your hardware:**
- Each CP VM has 20GB disk. Longhorn replication across 3 nodes means 3x storage consumption
- Recommendation: Add a second disk to VMs (50GB+) dedicated to Longhorn, separate from the OS disk
- Pi 5 with NVMe can also contribute to Longhorn pool (good for arm64 replica)
- Media Pi should NOT be in the Longhorn pool (different VLAN, different purpose)

**For Ghost specifically**: SQLite is the default and works fine. Don't add MySQL/PostgreSQL complexity unless you need it. Use a Longhorn PVC for the content directory.

---

### 5. Networking Recommendations

**N1. MetalLB** (Recommended)
Assign a pool in your VLAN 10 range, e.g., `192.168.10.200-192.168.10.220`. This gives LoadBalancer-type services external IPs. Essential for ingress.

**N2. Ingress controller: ingress-nginx** (Recommended)
You planned this already. Good choice - more widely used in production than Traefik, better for portfolio demonstration. K3s ships with Traefik by default, so disable it with `--disable=traefik` (already in your roadmap).

**N3. DNS strategy**
- Internal: Use your AdGuard Home on the router for `*.homelab.local` pointing to MetalLB IP
- External: Cloudflare for `3145.blog` pointing to your public IP (or Cloudflare Tunnel)
- Recommendation: Use **Cloudflare Tunnel** instead of port forwarding. More secure, no need to expose ports, and it's free.

**N4. Consider network policies**
Once the cluster is running, add Kubernetes NetworkPolicies to isolate namespaces. Great for security and excellent portfolio content. K3s uses Flannel by default which doesn't support NetworkPolicies - switch to Calico or install a Flannel + network policy controller.

---

### 6. GitOps: ArgoCD vs Flux

Both are excellent. For your goals:

| Factor | ArgoCD | Flux |
|--------|--------|------|
| UI | Rich web UI | CLI-only (UI via Weave GitOps) |
| Learning curve | Moderate | Steeper |
| Job market demand | Higher | Growing |
| Resource usage | Heavier (~500MB RAM) | Lighter (~200MB RAM) |
| Portfolio value | Strong (employers know it) | Good |

**Recommendation: ArgoCD.** The web UI is valuable for demonstrating your setup in blog posts and interviews. Job postings mention ArgoCD more frequently. The App of Apps pattern in your roadmap is the right approach.

---

### 7. Monitoring Stack

**Recommendation: kube-prometheus-stack via Helm**

This gives you Prometheus, Grafana, Alertmanager, and node-exporter in one deployment. Add Loki for logs in a later phase.

**Resource warning**: The full kube-prometheus-stack is memory-hungry (~1-2GB). On your resource-constrained cluster:
- Reduce Prometheus retention to 7 days
- Disable components you don't need initially (Thanos sidecar, etc.)
- Set resource limits to prevent OOM kills

---

### 8. Roadmap Assessment

The 7-phase roadmap in `docs/roadmap.md` is well-structured. A few notes:

**Phase 2 (Ansible)** - Add these to the playbook plan:
- SSH key distribution and hardening
- Time synchronization (chrony/NTP) - critical for etcd
- Set hostname properly on each node

**Phase 3 (ArgoCD)** - The roadmap examples use `yourusername` in GitHub URLs. Remember to update these.

**Phase 4 (Migration)** - The Ghost migration strategy is sound (parallel deploy, DNS cutover). One addition: export Ghost content as JSON backup before migration, in case the PVC migration has issues.

**Phase 5 (Monitoring)** - Consider adding Uptime Kuma alongside Prometheus. It's lightweight, gives you external endpoint monitoring, and you already use it.

**Phase 6 (CI/CD)** - Using a self-hosted GitHub runner in k3s is clever but be aware: the runner needs Docker-in-Docker or Kaniko for building images. This adds complexity. Start with simple validate/lint workflows.

---

### 9. Career & Portfolio Value

**High-impact things to demonstrate:**
1. **IaC with Terraform** - You have this. Add `terraform.tfvars.example` and `outputs.tf` to make it complete.
2. **Configuration management with Ansible** - Idempotent playbooks with roles, not just shell scripts.
3. **GitOps with ArgoCD** - App of Apps pattern, auto-sync, self-healing.
4. **Monitoring** - Custom Grafana dashboards with SLI/SLO thinking.
5. **Sealed Secrets** - Shows you understand secret management in K8s.
6. **Network Policies** - Shows security awareness.
7. **CI/CD** - Validate infra changes automatically.

**Blog post ideas that show depth:**
- "Why I chose k3s over k8s for my homelab (and what I'd do differently)"
- "Lessons from running a 3-node etcd cluster on a single host"
- "GitOps in practice: How I deploy with zero manual kubectl"
- "ARM64 + AMD64: Building a multi-arch K8s cluster"
- "From Docker Compose to Kubernetes: A migration guide"

---

### 10. Documentation Quality

**Strengths:**
- CLAUDE.md provides excellent context for AI assistants
- Roadmap is detailed with code examples
- README has clear architecture diagram
- .gitignore is comprehensive

**Issues:**
- README.md line 7: typo "contqns" should be "contains" (already in working directory as uncommitted change)
- README references `terraform.tfvars.example` in getting started, but this file doesn't exist
- Roadmap shows `telmate/proxmox` provider in examples but you actually use `bpg/proxmox`

---

## Concrete TODO List

### Immediate (before starting Phase 2)

- [ ] **Fix README typo**: "contqns" → "contains" on line 7
- [ ] **Create `terraform/proxmox/terraform.tfvars.example`**: Sanitized version for documentation
- [ ] **Create `terraform/proxmox/outputs.tf`**: Export VM IPs and names
- [ ] **Fix SSH key injection in main.tf**: Add `keys = [var.ssh_public_key]` to `user_account` block
- [ ] **Verify VLAN tagging**: Confirm `vmbr0` bridge handles VLAN 10 correctly, add `vlan_id` if needed
- [ ] **Verify Proxmox API user**: Ensure it's not using `root@pam`, create dedicated user if so

### Phase 2 (Ansible & k3s)

- [ ] Create Ansible inventory (`ansible/inventory/hosts.yml`)
- [ ] Write node preparation playbook (SSH hardening, firewall, NTP, swap off, kernel modules)
- [ ] Write k3s installation playbook (3 CP nodes with `--cluster-init`, disable Traefik)
- [ ] Write Pi worker join playbook
- [ ] Set up kubeconfig on local machine
- [ ] Verify all nodes `Ready` with `kubectl get nodes`
- [ ] Consider increasing VM disk to 32GB before k3s install

### Phase 3 (GitOps)

- [ ] Install ArgoCD via Kustomize
- [ ] Set up App of Apps pattern with your actual GitHub repo URL
- [ ] Deploy MetalLB with IP pool `192.168.10.200-220`
- [ ] Deploy ingress-nginx
- [ ] Deploy cert-manager with Cloudflare DNS solver
- [ ] Install Sealed Secrets for secret management
- [ ] Configure Cloudflare Tunnel (instead of port forwarding)

### Phase 4 (Apps)

- [ ] Deploy Ghost with Longhorn PVC
- [ ] Export Ghost data from Docker as JSON backup
- [ ] Deploy Vaultwarden with NetworkPolicy
- [ ] DNS cutover for 3145.blog
- [ ] Deploy Uptime Kuma for external monitoring

### Future considerations

- [ ] Move Terraform state to remote backend (Phase 6)
- [ ] Add Loki for log aggregation (Phase 5)
- [ ] Evaluate Calico for NetworkPolicy support (Phase 3 or 4)
- [ ] Set up Velero for K8s backup/restore
- [ ] Add GitHub Actions for Terraform validate and K8s manifest linting (Phase 6)

---

## Architecture Decision Records (ADR)

For reference, key decisions and their rationale:

| Decision | Choice | Rationale |
|----------|--------|-----------|
| K8s distribution | k3s | Lightweight, ARM-friendly, single binary, good for homelab |
| Terraform provider | bpg/proxmox | Better maintained than telmate, fewer permission issues |
| VM OS | Ubuntu Server | Wide community support, cloud-init compatible, LTS available |
| Control plane count | 3 nodes | Proper etcd quorum, demonstrates HA concepts |
| GitOps tool | ArgoCD | Better UI, higher job market demand, good for blog content |
| Ingress | ingress-nginx | Industry standard, well-documented, good portfolio value |
| Storage | Longhorn → local-path initially | Start simple, add distributed storage when apps need it |
| Secrets | Sealed Secrets (planned) | Simple, Git-friendly, works offline, good for homelab |
| Load balancer | MetalLB | Standard for bare-metal K8s, integrates with ingress |

---

*This review is based on the repository state at commit `994a1a3`. It should be updated as the project progresses through its phases.*
