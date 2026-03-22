# Homelab

![k3s](https://img.shields.io/badge/k3s-v1.31-326CE5?logo=kubernetes&logoColor=white)
![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-EF7B4D?logo=argo&logoColor=white)
![SOPS](https://img.shields.io/badge/Secrets-SOPS_Encrypted-black?logo=mozilla&logoColor=white)
![CI](https://github.com/Thomas-3145/homelab/actions/workflows/lint.yaml/badge.svg)

I'm a student learning DevOps on the side. Instead of just reading theory about Kubernetes and Terraform, I built this — my homelab. From pretty much scratch, with zero prior knowledge of any of it.

I learn better by doing first — hands-on before the theory hits in school, then more practice in the homelab afterwards.



The goal is to land a job as a DevOps engineer, with a focus on infrastructure rather than the dev side. This repo is my hands-on proof of that learning.

The parts I've enjoyed most: Terraform, Ansible, GitOps, and getting backups right.

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

## Stack

### Terraform
Provisions all VMs on Proxmox. Before this, I was clicking through the UI every time — Terraform made it repeatable and fast. One command to spin up the entire cluster.

### Ansible
Configures the nodes after provisioning: packages, sysctl, swap, k3s installation. Same idea as Terraform — no manual SSH and running commands by hand.

### k3s
Lightweight Kubernetes. Full upstream k8s would be overkill for a homelab, k3s gives the same API surface with less overhead. I also have a separate lab VM for learning kubeadm and "raw" Kubernetes.

### ArgoCD (GitOps)
Everything in the cluster is defined in this repo. ArgoCD watches Git and applies changes automatically — I never run `kubectl apply` manually. If I want to change something, I edit a file and push. This is the part that clicked hardest for me.

### MetalLB + ingress-nginx
Bare-metal clusters don't have a cloud load balancer. MetalLB fills that gap by assigning real IPs from my LAN range. ingress-nginx handles routing from those IPs into the cluster

### cert-manager
Automated TLS certificates via Let's Encrypt and Cloudflare DNS challenge. Every service gets HTTPS without touching anything manually.

### SOPS + KSOPS
Secrets are encrypted and committed directly to Git. I can keep the repo public without exposing passwords or API keys — the cluster decrypts them at apply time using an age key.

### Cloudflare Tunnel
Exposes services externally without opening any ports on my router. Traffic goes Cloudflare → tunnel → cluster. No port forwarding, no exposed public IP.

### Longhorn
Distributed block storage across the cluster nodes. Needed for stateful workloads (databases, etc.) that need to survive a node going down.

### Prometheus + Grafana + Loki
Metrics, dashboards, and logs in one stack. Grafana for investigation, Prometheus for collection, Loki for centralized logs from all pods.

### Alertmanager + ntfy
Alerts go to my phone via ntfy. I'd rather get a notification when something breaks than discover it when I go looking.

### Velero + Garage
Velero backs up Kubernetes workloads. Garage is a self-hosted S3-compatible store (running on the cluster) that receives those backups. Follows a 3-2-1 strategy: local, Media Pi, and Cloudflare R2 off-site.


One goal is to be able to self-host a few services with full HA.

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
