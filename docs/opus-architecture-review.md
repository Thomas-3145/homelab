# Architecture Review & Recommendations

> **Date**: 2026-03-15 (Updated)
> **Original Review**: 2026-02-14 (Claude Opus 4.6, Phase 1)
> **Updated Review**: 2026-03-08 (Claude Opus 4.6, Phase 3-4)
> **Updated Review**: 2026-03-15 (Claude Sonnet 4.6, Phase 4)
> **Project**: Thomas's Homelab - K3s Infrastructure
> **Current Phase**: Phase 4 — Garage → Velero → App migration

---

## Executive Summary

### Original Assessment (Feb 2026)

The project had a solid foundation with clean Terraform, well-planned roadmap, and 3 control plane VMs provisioned on Proxmox. The recommendation was to shift from planning to execution.

### Updated Assessment (Mar 2026 — Week 2)

Execution continues to be **excellent**. The monitoring stack is complete and a full security hardening pass has been done. The cluster is now in a state worth calling production-quality for a homelab.

**Added since 2026-03-08:**
- kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
- Loki + Promtail for log aggregation
- Alertmanager → ntfy webhook for phone notifications
- Custom PrometheusRules (NodeDown, HighMemory, LonghornDegraded, CertExpiring)
- Security hardening: pinned all container images, added securityContext, resource limits, health probes
- Headlamp RBAC: replaced cluster-admin with read-only ClusterRole
- Terraform: removed hardcoded VM password

**Key findings:**
1. **Architecture** — Production-quality patterns. GitOps-first approach is disciplined and consistent
2. **Security** — Significantly improved. SOPS/KSOPS for secrets, securityContext on all pods, least-privilege RBAC, pinned images
3. **Observability** — Full stack now: metrics (Prometheus), logs (Loki), dashboards (Grafana), alerts (ntfy)
4. **Code quality** — Pre-commit hooks, conventional commits, clean YAML. Professional standard
5. **Gaps** — No network policies, Terraform state still local, SOPS bootstrap not documented
6. **Portfolio value** — High. Demonstrates real infrastructure engineering end-to-end

**Overall: 8.5/10** — Strong fundamentals, observability complete, security hardened. Remaining gap is the backup chain (Garage + Velero) before app migration.

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

### New Recommendations Completed (2026-03-15)

| Rec | Status | Notes |
|---|---|---|
| R3: Resource limits | ✅ Done | Added to homepage, headlamp, it-tools |
| R4: Monitoring stack | ✅ Done | kube-prometheus-stack + Loki + Promtail + ntfy |
| Pod Security Standards | ✅ Done | securityContext on all pods (runAsNonRoot, no privilege escalation, capabilities dropped) |
| Image pinning | ✅ Done | All images pinned to specific versions |
| Headlamp RBAC | ✅ Done | cluster-admin → read-only ClusterRole |
| Terraform hardcoded password | ✅ Done | Removed password = "ubuntu" from cloud-init |

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
- **SOPS bootstrap documentation** — how to recover if the age key is lost?
- **Terraform state encryption** — local state file is readable by anyone with disk access
- **Renovate** — images are now pinned but will go stale without automated update PRs

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

**R3. Add resource limits to all deployments** ✅ Done 2026-03-15

### Medium Priority

**R4. Monitoring stack** ✅ Done 2026-03-15
kube-prometheus-stack + Loki + Promtail deployed. Alertmanager → ntfy for phone notifications. Custom PrometheusRules for node, Longhorn, and certificate alerts.

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
1. **Backup chain** (Garage + Velero) — shows production thinking *(next up)*
2. ~~**Monitoring** (Prometheus + Grafana)~~ ✅ Done
3. **At least one app migration** (Ghost) — shows real-world Kubernetes usage

### Interview talking points:
- "I reversed my roadmap order to implement backups before migrating critical services"
- "I chose SOPS over Sealed Secrets because I wanted secrets encrypted in Git, not just in the cluster"
- "The cluster runs mixed amd64/arm64 — real multi-arch, not just a label"
- "Every change goes through Git. I haven't run kubectl apply manually since Phase 3"

---

*Last updated 2026-03-15. Previous snapshot: commit `a495295`, cluster state 2026-03-08.*
