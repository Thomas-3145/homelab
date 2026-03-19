# Homelab Infrastructure

![CI](https://github.com/Thomas-3145/homelab/actions/workflows/lint.yaml/badge.svg)
![k3s](https://img.shields.io/badge/k3s-v1.31-326CE5?logo=kubernetes&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-1.x-844FBA?logo=terraform&logoColor=white)
![Ansible](https://img.shields.io/badge/Ansible-Managed-EE0000?logo=ansible&logoColor=white)
![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-EF7B4D?logo=argo&logoColor=white)
![Longhorn](https://img.shields.io/badge/Longhorn-v1.11-5F259F?logo=rancher&logoColor=white)
![Nodes](https://img.shields.io/badge/Nodes-4_(3_CP_+_1_ARM64)-2496ED?logo=proxmox&logoColor=white)
![IaC Lines](https://img.shields.io/badge/Lines_of_IaC-1.5k+-green?logo=codeclimate&logoColor=white)
![K8s Manifests](https://img.shields.io/badge/K8s_Manifests-29-326CE5?logo=kubernetes&logoColor=white)
![Security](https://img.shields.io/badge/Trivy-0_Critical-success?logo=aquasecurity&logoColor=white)
![SOPS](https://img.shields.io/badge/Secrets-SOPS_Encrypted-black?logo=mozilla&logoColor=white)

> Modern homelab setup with GitOps, demonstrating Infrastructure as Code (IaC) and cloud-native practices.

## Overview

This repository contains the complete infrastructure setup for my homelab - from bare metal to applications. It's designed to be reproducible, documented, and showcase modern DevOps practices for professional development.

**Key Features:**
- 🚀 **GitOps-based**: Everything defined in code, deployed automatically
- 🏗️ **Infrastructure as Code**: Terraform for provisioning, Ansible for configuration
- ☸️ **Kubernetes (k3s)**: Lightweight, production-ready orchestration
- 🔄 **High Availability**: 3-node HA control plane with embedded etcd
- 📊 **Observability**: Prometheus + Grafana + Loki + Alertmanager → ntfy
- 💾 **3-2-1 Backups**: Velero → Garage → Media Pi → Cloudflare R2
- 🔒 **Security First**: Cert-manager for SSL, proper network segmentation

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   GL.iNet Flint 2 Router                    │
│          OpenWrt • AdGuard DNS • Tailscale • VLANs          │
└──────────────────────┬──────────────────────────────────────┘
                       │
                  VLAN 10 (homelab)
                  192.168.10.0/24
                       │
          ┌────────────┼────────────┐
          │            │            │
          ▼            ▼            ▼
    ┌──────────┐  ┌─────────┐  ┌─────────┐
    │ Proxmox  │  │ Homelab │  │  Cloud  │
    │ .10.20   │  │ Pi      │  │ (future)│
    │ 32GB RAM │  │ .10.11  │  │  AWS    │
    │ 6-core   │  │ 8GB RAM │  │         │
    └────┬─────┘  └────┬────┘  └─────────┘
         │             │
         │  k3s HA Cluster
         │  ┌──────────────────────┐
         ├──│ k3s-cp-01  .10.21   │
         ├──│ k3s-cp-02  .10.22   │
         └──│ k3s-cp-03  .10.23   │
            └──────────────────────┘
```

**Infrastructure:**
- **Proxmox Host** (192.168.10.20): HP EliteDesk 800 G4 - i5-8500T, 32GB RAM, 1.2TB storage
- **Homelab Pi** (192.168.10.11): Raspberry Pi 5 - 8GB RAM, 512GB NVMe (k3s worker)
- **Cloud** (planned): AWS integration for hybrid cloud setup

## Tech Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **IaC** | Terraform | Provision VMs on Proxmox |
| **Configuration** | Ansible | Configure nodes, install k3s |
| **Orchestration** | k3s | Lightweight Kubernetes distribution |
| **GitOps** | ArgoCD | Automated deployment from Git |
| **Storage** | Longhorn | Distributed block storage |
| **Ingress** | ingress-nginx | Reverse proxy & load balancer |
| **Certificates** | cert-manager | Automated SSL/TLS via Let's Encrypt |
| **Load Balancer** | MetalLB | Bare-metal load balancer for services |
| **Secrets** | SOPS + KSOPS | Encrypted secrets in Git |
| **Tunnel** | Cloudflared | Cloudflare Tunnel for external access |
| **Monitoring** | Prometheus + Grafana | Metrics & visualization |
| **Logging** | Loki + Promtail | Log aggregation |
| **Alerting** | Alertmanager → ntfy | Proactive notifications |
| **Backup** | Velero + Garage | Kubernetes workload backups |
| **Off-site** | Cloudflare R2 | Off-site backup (3-2-1 strategy) |

## Repository Structure

```
homelab/
├── terraform/
│   └── proxmox/           # VM provisioning (bpg/proxmox provider)
│
├── ansible/
│   ├── inventory/         # Host definitions
│   └── playbooks/         # k3s setup, node preparation
│
├── kubernetes/
│   ├── bootstrap/         # ArgoCD root app (App of Apps)
│   ├── infrastructure/    # Core cluster components
│   │   ├── argocd/       # GitOps engine + Application manifests
│   │   ├── cert-manager/ # SSL via Let's Encrypt + Cloudflare
│   │   ├── cloudflared/  # Cloudflare Tunnel
│   │   ├── garage/       # S3-compatible object storage (backup target)
│   │   ├── ingress-nginx/# Ingress controller (via ArgoCD)
│   │   ├── longhorn/     # Distributed storage (via ArgoCD)
│   │   ├── metallb/      # Bare-metal load balancer
│   │   ├── monitoring/   # ServiceMonitors for Prometheus
│   │   ├── pdb/          # PodDisruptionBudgets
│   │   └── velero/       # Kubernetes backup operator
│   └── apps/              # Applications
│       ├── homepage/     # Dashboard (home.3145.blog)
│       ├── headlamp/     # K8s dashboard (headlamp.3145.blog)
│       └── it-tools/     # IT toolkit (tools.3145.blog)
│
└── docs/
    ├── adr-Architecture-Decision-Records/
    └── roadmap.md
```

## GitOps Workflow

```
 ┌──────────┐       ┌──────────┐       ┌──────────────┐
 │Developer │       │  GitHub  │       │  k3s Cluster │
 └────┬─────┘       └─────┬────┘       └───────┬──────┘
      │  1. git push      │                    │
      └──────────────────>│  2. ArgoCD polls   │
                          │<───────────────────│
                          │                    │
                          │  3. Detect changes │
                          │───────────────────>│
                          │                    │
                          │  4. Sync & deploy  │
                          │               ✅   │
                          │───────────────────>│
```

Once bootstrapped, all changes are made by:
1. Editing manifests in `kubernetes/`
2. Committing to Git
3. Pushing to GitHub
4. ArgoCD automatically applies changes

**No manual `kubectl apply` needed!**

## Getting Started

**Prerequisites:**
- Proxmox installed and configured
- Terraform installed locally
- Ansible installed locally
- SSH access to all nodes

**Quick Start:**
```bash
# 1. Clone repository
git clone https://github.com/Thomas-3145/homelab.git
cd homelab

# 2. Configure Terraform variables
cd terraform/proxmox
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Proxmox details

# 3. Provision VMs
terraform init && terraform apply

# 4. Prepare nodes (DNS, swap, packages)
ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/prepare-k3s.yaml

# 5. Install k3s HA cluster + fetch kubeconfig
ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/install-k3s.yaml

# 6. Verify
kubectl get nodes
```

## Roadmap

This project is built in phases. See [docs/roadmap.md](docs/roadmap.md) for detailed implementation plan.

**Current Status: Fase 4 complete, entering Fase 5 (app migration)**

- ✅ Terraform provisioning Proxmox VMs
- ✅ Ansible preparing nodes and installing k3s
- ✅ HA k3s cluster running (3 CP + 1 worker)
- ✅ ArgoCD with App of Apps pattern
- ✅ MetalLB (192.168.10.200-220)
- ✅ ingress-nginx + cert-manager (Let's Encrypt)
- ✅ SOPS + KSOPS for encrypted secrets
- ✅ Cloudflare Tunnel (cloudflared)
- ✅ Longhorn distributed storage (v1.11, 2 replicas)
- ✅ CI pipeline (Terraform, YAML, Ansible, Kubeconform, Trivy)
- ✅ Monitoring (Prometheus + Grafana + Loki + Promtail)
- ✅ Alerting (Alertmanager → ntfy)
- ✅ Velero backups (daily, CSI snapshots)
- ✅ 3-2-1 backup strategy (Garage → Media Pi → Cloudflare R2)
- ✅ Resource limits & PodDisruptionBudgets
- ⏳ Application migration (Ghost, Vaultwarden)

## Documentation

- [Roadmap](docs/roadmap.md) - Detailed implementation plan
- [ADR-001: Backup Strategy](docs/adr-Architecture-Decision-Records/001-backup-strategy.md)

## Blog Series

Follow my journey building this homelab on my blog:
- https://3145.blog/

## License

MIT License - Feel free to use this as inspiration for your own homelab!

---
