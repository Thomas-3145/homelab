# Homelab

![k3s](https://img.shields.io/badge/k3s-v1.31-326CE5?logo=kubernetes&logoColor=white)
![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-EF7B4D?logo=argo&logoColor=white)
![SOPS](https://img.shields.io/badge/Secrets-SOPS_Encrypted-black?logo=mozilla&logoColor=white)
![CI](https://github.com/Thomas-3145/homelab/actions/workflows/lint.yaml/badge.svg)

Complete infrastructure for my homelab — from bare metal to running applications. HA k3s cluster on Proxmox, fully managed with GitOps.

---

## What I think DevOps is

Honestly, I had no idea what DevOps was when I started this.

I knew I wanted to work with infrastructure rather than application development,
and I knew I learned better by doing than by reading. So I bought some hardware
and started breaking things. The term "DevOps" came later.

What I've landed on: it's about owning the full picture. Not just the
application, not just the servers — the entire flow from a git push to a
running service, including what happens when it breaks at 2am. The parts that
clicked hardest for me were infrastructure as code (if I can't reproduce it,
I don't really understand it) and GitOps (Git as the single source of truth
for everything in the cluster).

I lean toward the infrastructure and platform side. I'm more interested in
building the foundation that lets others ship confidently than in the
application sitting on top of it. That's what this homelab is really about —
and it's the work I want to do.

---

## How my homelab works

1. **Terraform** provisions VMs on Proxmox
2. **Ansible** configures nodes and installs k3s
3. **ArgoCD** bootstraps the cluster (App of Apps pattern)
4. All applications are deployed via GitOps from this repo — no manual `kubectl apply`
5. **SOPS + KSOPS** encrypts secrets in Git, decrypted in-cluster at apply time
6. **Prometheus + Loki** collect metrics and logs, **Alertmanager** sends alerts to my phone
7. **Velero** backs up workloads nightly to **Garage** (self-hosted S3), forwarded off-site to Cloudflare R2

---

## Tech Stack

| | |
|---|---|
| **Infrastructure** | Proxmox, Terraform, Ansible |
| **Kubernetes** | k3s (HA, 3-node embedded etcd) |
| **GitOps** | ArgoCD (App of Apps) |
| **Networking** | VLANs, MetalLB, ingress-nginx, Cloudflare Tunnel, Tailscale |
| **Storage** | Longhorn (distributed block storage) |
| **Observability** | Prometheus, Grafana, Loki, Promtail, Alertmanager |
| **Security** | SOPS + KSOPS, cert-manager (Let's Encrypt) |
| **Backups** | Velero, Garage (S3-compatible), Cloudflare R2 |

---

## Design Principles

- **Reproducibility**: everything defined as code — if I can't reproduce it, I don't understand it
- **Git as source of truth**: no manual changes to the cluster, ever
- **High availability where it matters**: 3-node control plane with embedded etcd
- **Observability first**: monitoring and alerting were not an afterthought
- **Backup and restore tested**, not just configured

---

## Challenges & Learnings

- Debugged CoreDNS failing to resolve external names — traced it to an IPv6 issue with `/etc/resolv.conf`, fixed by forwarding directly to `1.1.1.1`
- Replaced Traefik with MetalLB + ingress-nginx mid-project after understanding why bare-metal clusters need their own load balancer
- Got SOPS working with ArgoCD (KSOPS) so secrets can live encrypted in a public repo
- Upgraded Longhorn from 1.8 to 1.11 in production without downtime
- Learned the difference between HA (Longhorn replication) and backup (Velero) — they solve different problems

---

## Architecture

```
                          Internet
                              |
                     Cloudflare Tunnel
                              |
              ┌───────────────────────────────┐
              │      GL.iNet Flint 2          │
              │  OpenWrt · AdGuard · Tailscale│
              └───────────┬───────────────────┘
                          │
              ┌───────────┴───────────┐
              │                       │
         VLAN 10                  VLAN 20
      192.168.10.0/24          192.168.20.0/24
              │                       │
    ┌─────────────────┐      ┌─────────────────┐
    │  Proxmox Host   │      │      3145        │
    │  HP EliteDesk   │      │  Raspberry Pi 5  │
    │  i5-8500T 32GB  │      │  8GB · 512GB SSD │
    └────────┬────────┘      │  PBS · arr-stack │
             │               │  Garage · ntfy   │
     k3s HA Cluster          └─────────────────┘
     ┌────────────────────┐
     │  k3s-cp-01  .10.21 │  Control Plane (x3)
     │  k3s-cp-02  .10.22 │  embedded etcd
     │  k3s-cp-03  .10.23 │
     └────────────────────┘
     ┌────────────────────┐
     │  k3s-worker-01     │  Worker VM (temporary)
     │  (VM on Proxmox)   │
     └────────────────────┘
```

---

## Getting Started

This repo isn't meant to be copy-pasted — it's built around specific hardware. But the general flow is:

```bash
# 1. Provision VMs
cd terraform/proxmox && terraform apply

# 2. Configure nodes and install k3s
ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/install-k3s.yaml

# 3. Bootstrap ArgoCD — it takes it from there
kubectl apply -k kubernetes/bootstrap/
```

---

## Repository Structure

```
homelab/
├── terraform/proxmox/     # VM provisioning
├── ansible/               # Node configuration + k3s install
├── kubernetes/
│   ├── bootstrap/         # ArgoCD root app (App of Apps)
│   ├── infrastructure/    # Core cluster components
│   └── apps/              # Applications
└── docs/                  # ADRs and roadmap
```

## Roadmap

See [docs/roadmap.md](docs/roadmap.md) for the full plan.

- [x] Terraform + Ansible + k3s HA cluster
- [x] ArgoCD (App of Apps pattern)
- [x] MetalLB + ingress-nginx + cert-manager
- [x] SOPS + KSOPS encrypted secrets
- [x] Cloudflare Tunnel
- [x] Longhorn distributed storage
- [x] Monitoring (Prometheus + Grafana + Loki)
- [x] Alerting (Alertmanager → ntfy)
- [x] Velero + Garage backups (3-2-1)
- [ ] Ghost + Vaultwarden migration to k3s
- [ ] AWS integration (separate project)
