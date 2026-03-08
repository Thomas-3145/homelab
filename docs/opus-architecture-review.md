# Architecture Review & Recommendations

> **Date**: 2026-03-08 (Updated)
> **Original Review**: 2026-02-14 (Claude Opus 4.6, Phase 1)
> **Updated Review**: 2026-03-08 (Claude Opus 4.6, Phase 3-4)
> **Project**: Thomas's Homelab - K3s Infrastructure
> **Current Phase**: Phase 3 complete, entering Phase 4

---

## Executive Summary

### Original Assessment (Feb 2026)

The project had a solid foundation with clean Terraform, well-planned roadmap, and 3 control plane VMs provisioned on Proxmox. The recommendation was to shift from planning to execution.

### Updated Assessment (Mar 2026)

Execution has been **excellent**. In three weeks, the project went from "Terraform works" to a fully operational GitOps-managed k3s cluster with:
- HA control plane (3 nodes) + ARM64 worker
- ArgoCD with App of Apps pattern
- MetalLB + ingress-nginx + cert-manager (full ingress stack)
- Longhorn distributed storage (v1.11.x)
- SOPS/KSOPS for encrypted secrets in Git
- Cloudflare Tunnel for external access
- PBS for VM backups
- NUT UPS for graceful shutdowns
- 6+ deployed applications

**Key findings:**
1. **Architecture** — Production-quality patterns. GitOps-first approach is disciplined and consistent
2. **Security** — SOPS/KSOPS is a better choice than the originally recommended Sealed Secrets. Network segmentation solid with VLANs + Tailscale
3. **Code quality** — Pre-commit hooks, conventional commits, clean YAML. Professional standard
4. **Gaps** — No monitoring stack yet, no network policies, Terraform state still local, SOPS bootstrap not automated
5. **Portfolio value** — High. This demonstrates real infrastructure engineering, not just tutorials copy-pasted

**Overall: 8/10** — A mature, well-architected homelab that demonstrates strong DevOps fundamentals.

---

## What Changed Since Original Review

### Completed Recommendations

| Original Rec | Status | Notes |
|---|---|---|
| T3: terraform.tfvars.example | ✅ Done | Created with sanitized values |
| T1: outputs.tf | ✅ Done | Exports CP IPs, names, IDs |
| S4: Secrets management | ✅ Done | SOPS/KSOPS (not Sealed Secrets as suggested) |
| N1: MetalLB | ✅ Done | 192.168.10.200-220 pool |
| N2: ingress-nginx | ✅ Done | Replaced Traefik |
| N3: Cloudflare Tunnel | ✅ Done | cloudflared in cluster |
| Phase 2: Ansible | ✅ Done | 7 playbooks, clean inventory |
| Phase 3: ArgoCD | ✅ Done | App of Apps, 10 applications |

### Still Outstanding

| Original Rec | Status | Notes |
|---|---|---|
| T2: Remote state backend | ❌ Still local | Low risk for single-user, but fragile |
| T5: VLAN tag in Terraform | ❓ Unverified | Bridge may handle this at Proxmox level |
| S2: Dedicated Proxmox API user | ❓ Unverified | May still use root@pam |
| S3: SSH hardening | Partial | Ansible sets keys, but no fail2ban/UFW playbook |
| N4: Network policies | ❌ Not done | Flannel doesn't support them without extra work |

---

## Detailed Analysis (Updated)

### 1. Terraform

**Status: Solid, unchanged since Phase 1**

The Terraform code is clean and functional. Provider pinning (`bpg/proxmox >= 0.50.0`), proper variable handling, and cloud-init integration all work well.

**Remaining issues:**
- **Local state only** — If the machine dies, state is lost. Acceptable for homelab but worth backing up. Consider adding a periodic `terraform state pull > backup.tfstate` to PBS.
- **No data sources** — Template VM ID 9000 is assumed to exist. A `data` source could validate this.
- **Agent disabled** — `agent.enabled = false` works but Proxmox guest agent would provide better VM management (IP reporting, graceful shutdown).

### 2. Ansible

**Status: Professional quality, well-structured**

7 playbooks covering the full lifecycle: node prep → k3s install → worker join → Traefik removal → Longhorn prep.

**Strengths:**
- Three-play design in install-k3s.yaml (bootstrap → join → kubeconfig) is elegant
- Proper handler usage for service restarts
- Handles Pi 5 quirks (dphys-swapfile vs fstab for swap)
- Tailscale IP in inventory shows network sophistication

**Room for improvement:**
- Playbooks are flat — could benefit from roles for reusability
- Hardcoded IPs (192.168.10.21) appear in multiple places
- No Ansible Vault for local secrets
- Missing: fail2ban, UFW, unattended-upgrades playbook (currently done manually)

### 3. Kubernetes & GitOps

**Status: Excellent — the strongest part of the project**

The App of Apps pattern is textbook:
```
root-app.yaml → applications/ → {metallb, ingress-nginx, cert-manager,
                                  longhorn, cloudflared, homepage,
                                  headlamp, it-tools, ...}
```

**What's well done:**
- Every component managed by ArgoCD — no manual `kubectl apply`
- Automated sync with selfHeal and prune enabled
- SOPS/KSOPS integration via ArgoCD repo-server patch
- Consistent structure across all Application manifests
- Proper sync waves for dependency ordering
- Version pinning with minor wildcard (e.g., `1.11.*`)

**SOPS/KSOPS integration:**
The repo-server patch adds an initContainer that installs ksops and kustomize, mounts age keys, and sets XDG_CONFIG_HOME. This is clean but worth documenting as a bootstrap dependency — the `sops-age-key` Secret must be created manually before ArgoCD can decrypt anything.

**Applications deployed:**
| App | Type | Quality |
|-----|------|---------|
| ArgoCD | GitOps controller | ✅ Well-configured |
| MetalLB | Load balancer | ✅ With ignoreDifferences fix |
| ingress-nginx | Ingress controller | ✅ Standard setup |
| cert-manager | TLS certificates | ✅ Cloudflare DNS solver |
| Longhorn | Distributed storage | ✅ Upgraded to 1.11.x |
| cloudflared | Tunnel | ✅ SOPS-encrypted token |
| Homepage | Dashboard | ✅ Rich config with widgets |
| Headlamp | K8s UI | ✅ Clean deployment |
| IT-Tools | Utilities | ✅ Simple and working |

### 4. Security

**Improved significantly since original review.**

**Strengths:**
- SOPS/KSOPS — secrets encrypted in Git, never plaintext
- Cloudflare Tunnel — no port forwarding, no exposed services
- VLAN segmentation — homelab isolated from LAN
- Tailscale — encrypted mesh for cross-VLAN communication
- Pre-commit hooks — enforce code quality before it reaches Git
- Let's Encrypt TLS — all ingresses use HTTPS

**Still missing:**
- **Network Policies** — all pods can reach all pods. Flannel doesn't support NetworkPolicy natively. Options: Calico CNI, or Cilium (more complex but powerful)
- **Pod Security Standards** — no restrictions on privileged containers, root users, or capabilities
- **RBAC granularity** — ServiceAccounts exist but no fine-grained role definitions beyond defaults
- **SOPS bootstrap documentation** — how to recover if the age key is lost?
- **Terraform state encryption** — local state file is readable by anyone with disk access

### 5. Documentation

**Exceptional quality.** The roadmap alone is 961 lines with clear success criteria per phase.

| Doc | Quality | Notes |
|-----|---------|-------|
| README.md | ✅ | Professional with architecture diagram |
| roadmap.md | ✅ | 8 phases, detailed tasks, code examples |
| ADR-001 (backup) | ✅ | Full decision journey documented |
| commit-guide.md | ✅ | Clear conventional commits guide |
| CLAUDE.md | ✅ | Excellent AI assistant context |

**Issue:** The roadmap still shows Phase 3 as in-progress and some code examples reference `telmate/proxmox` provider (you use `bpg/proxmox`). Worth a cleanup pass.

---

## New Recommendations

### High Priority

**R1. Complete backup chain before app migration** (Phase 4 prerequisite)
The ADR-001 decision is sound: Longhorn → Garage → Velero → R2. Don't migrate Ghost/Vaultwarden until at least Garage + Velero are working. A failed migration of your password manager would be painful.

**R2. Document SOPS bootstrap process**
Create a `docs/sops-bootstrap.md` or add to README:
1. How to generate age key
2. How to create the `sops-age-key` Secret in cluster
3. How to recover if key is lost
4. Where the private key is stored (and backed up)

This is critical knowledge that currently exists only in your head.

**R3. Add resource limits to all deployments**
None of the deployed apps have CPU/memory requests or limits. One runaway pod could starve the cluster. At minimum, add limits to Homepage, Headlamp, and IT-Tools.

### Medium Priority

**R4. Monitoring stack** (Phase 5)
You're running blind right now. kube-prometheus-stack gives you:
- Node health (CPU, RAM, disk per node)
- Pod restarts and failures
- Longhorn volume health
- etcd cluster metrics

With your resource constraints, set Prometheus retention to 3-7 days and disable components you don't need.

**R5. Ansible roles refactor**
Current flat playbook structure works but doesn't scale. Reorganize:
```
ansible/roles/
  common/       # DNS, swap, packages
  k3s-server/   # CP node setup
  k3s-agent/    # Worker setup
  longhorn/     # Storage prerequisites
  hardening/    # SSH, fail2ban, UFW
```

**R6. Terraform state backup**
Add a cron job or script to back up `terraform.tfstate` to PBS or Garage. If your machine dies, you lose the ability to manage VMs through Terraform.

### Low Priority

**R7. Network Policies**
Consider Calico CNI for NetworkPolicy support. At minimum, isolate namespaces so Homepage can't reach cert-manager internals.

**R8. Pod Security Standards**
Add `pod-security.kubernetes.io/enforce: baseline` labels to namespaces. This prevents privileged containers without requiring Kyverno.

**R9. Update roadmap.md**
Mark Phase 1-3 as complete, update code examples that reference wrong provider, and adjust timelines.

---

## Architecture Decision Records Update

| Decision | Original Choice | Current Status |
|----------|----------------|----------------|
| K8s distribution | k3s | ✅ Correct — running well |
| Terraform provider | bpg/proxmox | ✅ Correct |
| VM OS | Ubuntu Server | ✅ Correct |
| Control plane count | 3 nodes | ✅ Working HA |
| GitOps tool | ArgoCD | ✅ Excellent choice |
| Ingress | ingress-nginx | ✅ Deployed, replaced Traefik |
| Storage | Longhorn | ✅ v1.11.x, 2 replicas |
| Secrets | ~~Sealed Secrets~~ → SOPS/KSOPS | ✅ Better choice — encrypts in Git |
| Load balancer | MetalLB | ✅ L2 mode, 192.168.10.200-220 |
| External access | Cloudflare Tunnel | ✅ Added (not in original plan) |
| VM backups | PBS on Media Pi | ✅ Added (ARM64 build) |
| Object storage | ~~MinIO~~ → Garage | Planned (not deployed yet) |
| K8s backups | Velero + CSI | Planned (not deployed yet) |

---

## Portfolio Readiness

### Ready to show employers now:
- Infrastructure as Code (Terraform + Ansible)
- GitOps with ArgoCD (App of Apps pattern)
- HA Kubernetes cluster (mixed architecture)
- Encrypted secrets management (SOPS/KSOPS)
- Professional documentation and ADRs
- Clean Git history with conventional commits

### Complete before highlighting on CV:
1. **Backup chain** (Garage + Velero) — shows production thinking
2. **Monitoring** (Prometheus + Grafana) — shows observability awareness
3. **At least one app migration** (Ghost) — shows real-world Kubernetes usage

### Interview talking points:
- "I reversed my roadmap order to implement backups before migrating critical services"
- "I chose SOPS over Sealed Secrets because I wanted secrets encrypted in Git, not just in the cluster"
- "The cluster runs mixed amd64/arm64 — real multi-arch, not just a label"
- "Every change goes through Git. I haven't run kubectl apply manually since Phase 3"

---

*This review is based on the repository state at commit `a495295` (rewritten) and live cluster state on 2026-03-08.*
