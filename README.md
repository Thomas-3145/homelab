# Homelab Infrastructure

> Modern homelab setup with GitOps, demonstrating Infrastructure as Code (IaC) and cloud-native practices.

## Overview

This repository contains the complete infrastructure setup for my homelab - from bare metal to applications. It's designed to be reproducible, documented, and showcase modern DevOps practices for professional development.

**Key Features:**
- 🚀 **GitOps-based**: Everything defined in code, deployed automatically
- 🏗️ **Infrastructure as Code**: Terraform for provisioning, Ansible for configuration
- ☸️ **Kubernetes (k3s)**: Lightweight, production-ready orchestration
- 🔄 **High Availability**: 3-node HA control plane with embedded etcd
- 📊 **Full Observability**: Prometheus + Grafana monitoring stack
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
- **Homelab Pi** (192.168.10.11): Raspberry Pi 5 - 8GB RAM, 256GB NVMe (future k3s worker)
- **Cloud** (planned): AWS integration for hybrid cloud setup

## Tech Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **IaC** | Terraform | Provision VMs on Proxmox & AWS resources |
| **Configuration** | Ansible | Configure nodes, install k3s |
| **Orchestration** | k3s | Lightweight Kubernetes distribution |
| **GitOps** | ArgoCD | Automated deployment from Git |
| **Storage** | Longhorn | Distributed block storage |
| **Ingress** | ingress-nginx | Reverse proxy & load balancer |
| **Certificates** | cert-manager | Automated SSL/TLS via Let's Encrypt |
| **Load Balancer** | MetalLB | Bare-metal load balancer for services |
| **Monitoring** | Prometheus + Grafana | Metrics & visualization |
| **CI/CD** | GitHub Actions | Automated testing & deployment |

## Repository Structure

```
homelab/
├── terraform/              # Infrastructure provisioning
│   ├── proxmox/           # Proxmox VMs (Ubuntu Server)
│   └── aws/               # AWS resources (future)
│
├── ansible/                # Configuration management
│   ├── inventory/         # Host definitions
│   ├── playbooks/         # Automation playbooks
│   └── roles/             # Reusable Ansible roles
│
├── kubernetes/             # Kubernetes manifests (GitOps)
│   ├── bootstrap/         # Initial ArgoCD setup
│   ├── infrastructure/    # Core cluster components
│   │   ├── argocd/       # GitOps engine
│   │   ├── cert-manager/ # SSL certificate management
│   │   ├── longhorn/     # Distributed storage
│   │   ├── metallb/      # Load balancer
│   │   └── ingress-nginx/# Ingress controller
│   └── apps/              # Applications
│       ├── ghost/        # Blog platform
│       ├── vaultwarden/  # Password manager
│       ├── github-runner/# Self-hosted CI runner
│       └── monitoring/   # Observability stack
│
├── scripts/                # Helper scripts
├── docs/                   # Documentation
│   ├── adr/               # Architecture Decision Records
│   ├── runbooks/          # Operational procedures
│   └── roadmap.md         # Implementation roadmap
└── README.md              # This file
```

## GitOps Workflow

```
Developer                 GitHub                   Cluster
    │                        │                        │
    │  1. Push changes       │                        │
    ├───────────────────────>│                        │
    │                        │                        │
    │                        │  2. ArgoCD detects     │
    │                        │     changes            │
    │                        ├───────────────────────>│
    │                        │                        │
    │                        │  3. Syncs & deploys    │
    │                        │                        │
    │                        │  4. Apps updated   ✓   │
    │                        │<───────────────────────│
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
git clone https://github.com/yourusername/homelab.git
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

**Current Status: 🏗️ Fase 3 - GitOps Bootstrap**

- ✅ Repository structure created
- ✅ Terraform provisioning Proxmox VMs
- ✅ Ansible preparing nodes and installing k3s
- ✅ HA k3s cluster running (3 control plane nodes)
- ⏳ ArgoCD / GitOps implementation
- ⏳ Application deployment
- ⏳ Monitoring stack

## Documentation

- [Roadmap](docs/roadmap.md) - Detailed implementation plan
- Network architecture - (coming soon)
- Disaster recovery plan - (coming soon)

## Blog Series

Follow my journey building this homelab on my blog:
- https://3145.blog/

## License

MIT License - Feel free to use this as inspiration for your own homelab!

---

**Built with** ☕ **and a passion for learning**
