# Homelab Infrastructure

> Modern homelab setup with GitOps, demonstrating Infrastructure as Code (IaC) and cloud-native practices.

## Overview

This repository contains the complete infrastructure setup for my homelab - from bare metal to applications. It's designed to be reproducible, documented, and showcase modern DevOps practices for professional development.

**Key Features:**
- 🚀 **GitOps-based**: Everything defined in code, deployed automatically
- 🏗️ **Infrastructure as Code**: Terraform for provisioning, Ansible for configuration
- ☸️ **Kubernetes (k3s)**: Lightweight, production-ready orchestration
- 🔄 **High Availability**: Multi-node setup across physical and cloud infrastructure
- 📊 **Full Observability**: Prometheus + Grafana monitoring stack
- 🔒 **Security First**: Cert-manager for SSL, proper network segmentation

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   GL.iNet Flint 2 Router                    │
│       OpenWrt • AdGuard DNS • Tailscale • VLANs            │
└──────────────────────┬──────────────────────────────────────┘
                       │
          ┌────────────┼────────────┐
          │            │            │
          ▼            ▼            ▼
    VLAN 10 (homelab)  │       VLAN 20 (media)
    192.168.10.0/24    │       192.168.20.0/24
          │            │            │
    ┌─────┴─────┐      │       ┌────┴────┐
    │           │      │       │         │
    ▼           ▼      │       ▼         │
┌─────────┐  ┌─────┐  │   ┌──────┐     │
│Proxmox  │  │Home │  │   │Media │     │
│ .10.20  │  │lab  │  │   │Pi    │     │
│ 32GB    │  │Pi   │  │   │.20.10│     │
│ 6-core  │  │.10  │  │   │8GB   │     │
│         │  │.11  │  │   │512GB │     │
└────┬────┘  └──┬──┘  │   └──────┘     │
     │          │     │                 │
     │ k3s HA Cluster│                 │
     │ (3 control    │                 │
     │  planes)      │                 │
     └───────────────┘                 │
                                       │
                                  ┌────┴────┐
                                  │   NFS   │
                                  │ Storage │
                                  └─────────┘
```

**Infrastructure:**
- **Proxmox Host** (192.168.10.20): HP EliteDesk 800 G4 - i5-8500T, 32GB RAM, 1.2TB storage
- **Homelab Pi** (192.168.10.11): Raspberry Pi 5 - 8GB RAM, 256GB NVMe
- **Media Pi** (192.168.20.10): Raspberry Pi 5 - 8GB RAM, 512GB NVMe (NAS/Storage)
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
│   ├── proxmox/           # Proxmox VMs (AlmaLinux 9)
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

# 3. Deploy infrastructure
terraform init
terraform apply

# 4. Bootstrap k3s cluster
cd ../../ansible
ansible-playbook -i inventory/hosts.yml playbooks/bootstrap-cluster.yml

# 5. Install ArgoCD and deploy apps
kubectl apply -k kubernetes/infrastructure/argocd/
kubectl apply -f kubernetes/bootstrap/

# Done! ArgoCD handles the rest.
```

## Roadmap

This project is built in phases. See [docs/roadmap.md](docs/roadmap.md) for detailed implementation plan.

**Current Status: 🏗️ Fase 1 - Terraform & Infrastructure**

- ✅ Repository structure created
- ✅ Documentation written
- 🚧 Terraform for Proxmox VMs
- ⏳ Ansible playbooks
- ⏳ k3s cluster setup
- ⏳ GitOps implementation
- ⏳ Application migration

## Documentation

- [Roadmap](docs/roadmap.md) - Detailed implementation plan
- Network architecture - (coming soon)
- Disaster recovery plan - (coming soon)

## Blog Series

Follow my journey building this homelab on my blog:
- [Blog link] - (add your blog URL)

## License

MIT License - Feel free to use this as inspiration for your own homelab!

---

**Built with** ☕ **and a passion for learning**
