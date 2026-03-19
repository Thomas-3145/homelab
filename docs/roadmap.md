# Homelab Roadmap

> Detailed implementation plan for building a production-ready homelab from scratch

## Project Goals

1. **Learning**: Hands-on experience with modern DevOps tools and practices
2. **Portfolio**: Demonstrate technical skills to potential employers
3. **Documentation**: Blog series documenting the journey and lessons learned
4. **Functionality**: Host real applications with high availability and proper monitoring

## Implementation Phases

---

## Fase 1: Infrastructure Provisioning (Terraform)

**Goal**: Automate VM creation on Proxmox using Infrastructure as Code

### Objectives
- Set up Terraform with Proxmox provider
- Create Ubuntu Server cloud-init template
- Define k3s node VMs in code
- Make infrastructure reproducible and versionable

### Tasks

#### 1.1 Proxmox API Setup
```bash
# In Proxmox web UI:
# 1. Create API token: Datacenter → Permissions → API Tokens
# 2. Create user: pveum user add terraform@pve
# 3. Assign permissions: pveum acl modify / -user terraform@pve -role PVEAdmin
```

**Deliverable**: API token and credentials for Terraform

#### 1.2 Terraform Provider Configuration
Create `terraform/proxmox/providers.tf`:
```hcl
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.95"
    }
  }
}

provider "proxmox" {
  pm_api_url      = "https://192.168.10.20:8006/api2/json"
  pm_api_token_id = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret
  pm_tls_insecure = true  # For self-signed cert
}
```

**Deliverable**: Working Terraform provider connection

#### 1.3 Ubuntu Server Template
Two options:

**Option A: Manual (Simpler for first time)**
1. Download Ubuntu Server cloud image
2. Create VM template in Proxmox
3. Add cloud-init drive
4. Convert to template

**Option B: Automated with Packer (Recommended)**
- Use Packer to build template from ISO
- Fully automated and reproducible
- Can be version controlled

```bash
# Download Ubuntu Server cloud image (22.04 LTS or 24.04 LTS)
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

# Import to Proxmox
qm create 9000 --name ubuntu-server-template --memory 2048 --net0 virtio,bridge=vmbr0
qm importdisk 9000 jammy-server-cloudimg-amd64.img local-lvm
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0
qm set 9000 --ide2 local-lvm:cloudinit
qm set 9000 --boot c --bootdisk scsi0
qm set 9000 --serial0 socket --vga serial0
qm set 9000 --agent enabled=1
qm template 9000
```

**Deliverable**: Ubuntu Server template ready for cloning

#### 1.4 Define k3s VMs in Terraform
Create `terraform/proxmox/vms.tf`:
```hcl
resource "proxmox_vm_qemu" "k3s_control_plane" {
  count       = 3
  name        = "k3s-cp-0${count.index + 1}"
  target_node = "proxmox"  # Your Proxmox node name
  clone       = "ubuntu-server-template"

  # Resource allocation
  cores   = 2
  memory  = 4096
  scsihw  = "virtio-scsi-pci"

  # Disk
  disk {
    size    = "32G"
    type    = "scsi"
    storage = "local-lvm"
  }

  # Network
  network {
    model  = "virtio"
    bridge = "vmbr0"
    tag    = 10  # VLAN 10 (homelab)
  }

  # Cloud-init
  ipconfig0 = "ip=192.168.10.2${count.index + 1}/24,gw=192.168.10.1"
  ciuser    = "thomas"
  sshkeys   = file("~/.ssh/id_rsa.pub")
}
```

**Deliverable**: 3 VMs created on Proxmox via `terraform apply`

#### 1.5 Testing & Validation
```bash
# Test Terraform plan
terraform plan

# Apply infrastructure
terraform apply

# Verify VMs are running
ssh thomas@192.168.10.21  # k3s-cp-01
ssh thomas@192.168.10.22  # k3s-cp-02
ssh thomas@192.168.10.23  # k3s-cp-03

# Destroy and recreate to test reproducibility
terraform destroy
terraform apply
```

**Deliverable**: Reproducible infrastructure that can be created/destroyed on demand

### Success Criteria
- ✅ Terraform successfully creates 3 Ubuntu Server VMs
- ✅ VMs have correct IPs in VLAN 10
- ✅ SSH access works with key authentication
- ✅ Infrastructure can be destroyed and recreated
- ✅ All code committed to Git

### Status: ✅ COMPLETE
### Blog Post: "Automating Proxmox VMs with Terraform"

---

## Fase 2: Configuration Management (Ansible)

**Goal**: Prepare nodes and install k3s cluster with high availability

### Objectives
- Configure Ubuntu Server nodes (DNS, packages, swap)
- Install k3s on control plane nodes (HA setup)
- Join Homelab Pi as worker node (future)
- Install Longhorn for distributed storage

### Tasks

#### 2.1 Ansible Inventory Setup
Create `ansible/inventory/hosts.yaml`:
```yaml
all:
  children:
    control_plane:
      hosts:
        k3s-cp-01:
          ansible_host: 192.168.10.21
        k3s-cp-02:
          ansible_host: 192.168.10.22
        k3s-cp-03:
          ansible_host: 192.168.10.23
      vars:
        k3s_role: server

    workers:
      hosts:
        homelab-pi:
          ansible_host: 192.168.10.11
      vars:
        k3s_role: agent

    k3s_cluster:
      children:
        - control_plane
        - workers
      vars:
        ansible_user: thomas
        ansible_python_interpreter: /usr/bin/python3
        k3s_version: v1.28.5+k3s1
```

**Deliverable**: Ansible can reach all nodes

#### 2.2 Node Preparation Playbook
Create `ansible/playbooks/01-prepare-nodes.yaml`:
- Update all packages
- Install required packages (curl, nfs-common, open-iscsi)
- Configure firewall (ufw for Ubuntu)
- AppArmor (enabled by default on Ubuntu)
- Disable swap
- Enable kernel modules for k3s

```yaml
---
- name: Prepare nodes for k3s
  hosts: k3s_cluster
  become: yes
  tasks:
    - name: Update apt cache
      apt:
        update_cache: yes
        cache_valid_time: 3600

    - name: Upgrade all packages
      apt:
        upgrade: dist

    - name: Install required packages
      apt:
        name:
          - curl
          - wget
          - git
          - nfs-common
          - open-iscsi
          - python3-pip
        state: present

    - name: Enable and configure UFW
      ufw:
        state: enabled
        policy: deny
        direction: incoming

    - name: Allow SSH
      ufw:
        rule: allow
        port: '22'
        proto: tcp

    - name: Allow k3s API server
      ufw:
        rule: allow
        port: '6443'
        proto: tcp

    - name: Allow kubelet
      ufw:
        rule: allow
        port: '10250'
        proto: tcp

    - name: Allow etcd
      ufw:
        rule: allow
        port: '2379:2380'
        proto: tcp

    - name: Disable swap
      command: swapoff -a

    - name: Disable swap permanently
      replace:
        path: /etc/fstab
        regexp: '^([^#].*?\sswap\s+sw\s+.*)$'
        replace: '# \1'
```

**Deliverable**: All nodes prepared and ready for k3s

#### 2.3 k3s HA Installation
Create `ansible/playbooks/02-install-k3s.yaml`:

**Step 1**: Install first control plane node
```yaml
- name: Initialize first k3s server
  hosts: k3s-cp-01
  become: yes
  tasks:
    - name: Install k3s
      shell: |
        curl -sfL https://get.k3s.io | sh -s - server \
          --cluster-init \
          --tls-san=192.168.10.20 \
          --tls-san=k3s.homelab.local \
          --disable=traefik \
          --write-kubeconfig-mode=644

    - name: Get k3s token
      slurp:
        src: /var/lib/rancher/k3s/server/node-token
      register: k3s_token
```

**Step 2**: Join additional control plane nodes
```yaml
- name: Join additional control plane nodes
  hosts: k3s-cp-02,k3s-cp-03
  become: yes
  tasks:
    - name: Join k3s cluster
      shell: |
        curl -sfL https://get.k3s.io | sh -s - server \
          --server https://192.168.10.21:6443 \
          --token {{ k3s_token.content | b64decode }} \
          --tls-san=192.168.10.20 \
          --disable=traefik \
          --write-kubeconfig-mode=644
```

**Step 3**: Join worker nodes
```yaml
- name: Join worker nodes
  hosts: workers
  become: yes
  tasks:
    - name: Join as agent
      shell: |
        curl -sfL https://get.k3s.io | sh -s - agent \
          --server https://192.168.10.21:6443 \
          --token {{ k3s_token.content | b64decode }}
```

**Deliverable**: 3-node HA k3s cluster + 1 worker

#### 2.4 Install Longhorn
Deploy Longhorn for distributed storage (via ArgoCD in Fase 3 or manually).

**Deliverable**: Longhorn installed and providing storage

#### 2.5 Kubeconfig Setup
Handled automatically by `install-k3s.yaml` Play 3 — fetches kubeconfig and replaces localhost IP.

**Deliverable**: kubectl working from local machine

### Success Criteria
- ✅ All nodes configured (DNS, swap, packages)
- ✅ 3-node HA k3s control plane running
- ✅ Homelab Pi joined as worker
- ⏳ Longhorn providing distributed storage
- ✅ kubectl commands work from local machine
- ✅ All nodes show "Ready" status

### Status: ✅ COMPLETE (cluster running, worker joined)
### Blog Post: "Building a HA k3s Cluster with Ansible"

---

## Fase 3: GitOps Bootstrap (ArgoCD)

**Goal**: Implement GitOps workflow for automated deployments

### Objectives
- Install ArgoCD in the cluster
- Configure "App of Apps" pattern
- Connect ArgoCD to GitHub repository
- Deploy infrastructure components via GitOps

### Tasks

#### 3.1 ArgoCD Installation
Create `kubernetes/infrastructure/argocd/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: argocd

resources:
  - https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  - ingress.yaml

patches:
  - patch: |-
      - op: replace
        path: /spec/type
        value: LoadBalancer
    target:
      kind: Service
      name: argocd-server
```

Install:
```bash
kubectl create namespace argocd
kubectl apply -k kubernetes/infrastructure/argocd/
```

**Deliverable**: ArgoCD running and accessible

#### 3.2 App of Apps Pattern
Create `kubernetes/bootstrap/root-app.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/ThBuKj/homelab.git
    targetRevision: main
    path: kubernetes/infrastructure
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

This single app will manage all other applications!

**Deliverable**: ArgoCD monitoring GitHub repository

#### 3.3 Deploy Infrastructure Components
Each component gets its own Application manifest:

`kubernetes/infrastructure/cert-manager/application.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/ThBuKj/homelab.git
    targetRevision: main
    path: kubernetes/infrastructure/cert-manager
  destination:
    server: https://kubernetes.default.svc
    namespace: cert-manager
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Repeat for:
- cert-manager
- ingress-nginx
- metallb
- longhorn (UI)

**Deliverable**: All infrastructure deployed via GitOps

#### 3.4 Configure MetalLB
Define IP pool for LoadBalancer services in VLAN 10:
```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: homelab-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.10.200-192.168.10.220
```

**Deliverable**: Services can get external IPs

#### 3.5 Configure cert-manager
Set up Let's Encrypt with Cloudflare DNS:
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: api-token
```

**Deliverable**: Automated SSL certificates

### Success Criteria
- ✅ ArgoCD installed and accessible
- ✅ Root app deployed and syncing (App of Apps)
- ✅ MetalLB assigning IPs (192.168.10.200-220)
- ✅ ingress-nginx deployed as LoadBalancer
- ✅ cert-manager issuing SSL certificates (Let's Encrypt + Cloudflare)
- ✅ SOPS + KSOPS for encrypted secrets
- ✅ Cloudflare Tunnel for external access
- ✅ Changes to GitHub trigger auto-deployment
- ✅ Longhorn distributed storage (v1.11, 2 replicas, snapshot restore verified)

### Status: ✅ COMPLETE
### Blog Post: "Implementing GitOps with ArgoCD"

---

## Fase 4: Backup & Storage

**Goal**: Complete backup infrastructure before migrating critical applications

### Objectives
- Deploy Garage as S3-compatible object storage
- Deploy Velero for Kubernetes workload backups
- Implement 3-2-1 backup strategy with off-site copies
- Add resource limits and PodDisruptionBudgets

### Completed

#### 4.1 Garage (S3-Compatible Storage)
- StatefulSet on Homelab Pi with local hostPath (not Longhorn — backup data separate from backed-up data)
- SOPS-encrypted RPC secret, managed by ArgoCD
- NodePort service (30900) for external access from Media Pi

#### 4.2 Velero
- Deployed via Helm, managed by ArgoCD
- Connects to Garage via S3-compatible API
- CSI snapshots for Longhorn volume backups
- Daily schedule (`daily-cluster`) at 02:00, 30-day TTL
- Prometheus alerts: VeleroBackupFailed, VeleroBackupMissing

#### 4.3 3-2-1 Backup Pipeline (COMPLETE)
Three copies, two devices, one off-site:

| Copy | Location | Method |
|------|----------|--------|
| 1. Original | Longhorn PVCs in k3s cluster | Live data |
| 2. On-site | Media Pi (rclone from Garage, 05:00 daily) | `rclone sync` via NodePort |
| 3. Off-site | Cloudflare R2 (rclone from Media Pi, 06:00 daily) | `rclone sync` to WEUR bucket |

VM backups handled separately: Proxmox → PBS on Media Pi (daily 04:00).

#### 4.4 Resource Requests/Limits
Added to all monitoring components (Prometheus, Grafana, Alertmanager, node-exporter, Loki, Promtail) based on `kubectl top` profiling.

#### 4.5 PodDisruptionBudgets
Added PDBs (`maxUnavailable: 1`) for: Prometheus, Grafana, Alertmanager, Loki, ingress-nginx, ArgoCD server/repo-server, cert-manager.

#### 4.6 Infrastructure Hardening
- Proxmox: e1000e EEE disabled (freeze fix), swap enabled, qemu-guest-agent on all VMs
- Unused VMs: autostart disabled (lab VM, study VM)

### Success Criteria
- ✅ Garage running as S3-compatible backup target
- ✅ Velero backing up all namespaces nightly
- ✅ 3-2-1 backup strategy fully operational (Garage → Media Pi → R2)
- ✅ Resource limits on all monitoring pods
- ✅ PDBs protecting critical services during node drains
- ✅ Proxmox stability issues resolved

### Status: ✅ COMPLETE
### Blog Posts: "Backing Up Kubernetes with Garage and Velero", "Velero Schedules, ServiceMonitors, and Keeping Dashboards in Git"

---

## Fase 5: Application Migration

**Goal**: Migrate critical applications from Docker (Media Pi) to k3s

### Objectives
- Deploy Ghost blog with Longhorn-backed persistent storage
- Deploy Vaultwarden with automated backups
- Configure ingress and SSL for all apps
- Verify Velero backups cover migrated apps

### Tasks

#### 5.1 Ghost Blog Migration
- Longhorn PVC for content storage
- Ingress with cert-manager TLS
- Verify Velero backup includes Ghost data

#### 5.2 Vaultwarden Migration
- Longhorn PVC for database
- Ingress with cert-manager TLS
- Verify Velero backup includes Vaultwarden data

### Success Criteria
- ⏳ Ghost blog accessible via HTTPS on k3s
- ⏳ Vaultwarden running with automated backups
- ⏳ All apps deployed via GitOps
- ⏳ Velero backing up application data

### Status: ⏳ NEXT UP
### Blog Post: "Deploying Apps on Kubernetes"

---

## Fase 6: Monitoring & Observability

**Goal**: Full visibility into cluster health and performance

### Completed

#### 6.1 kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
- Deployed via Helm, managed by ArgoCD
- Grafana at grafana.3145.blog with Let's Encrypt TLS
- Cluster Overview dashboard stored as ConfigMap in Git

#### 6.2 Loki + Promtail (Log Aggregation)
- Loki SingleBinary mode, Promtail as DaemonSet
- Logs queryable via Grafana

#### 6.3 Alerting (Alertmanager → ntfy)
Alerts configured:
- ✅ NodeDown, NodeHighMemory, NodeHighCPU
- ✅ LonghornDiskSpaceLow/Critical, LonghornVolumeDegraded
- ✅ VeleroBackupFailed, VeleroBackupMissing
- ✅ CertificateExpiringSoon

#### 6.4 ServiceMonitors
- cert-manager, Longhorn, Velero metrics flowing to Prometheus

#### 6.5 Renovate — Automated Dependency Updates (TODO)
- ⏳ Configure `renovate.json` for Helm chart and image version bumps
- ⏳ Auto-merge for patch updates, PR for minor/major

### Success Criteria
- ✅ Prometheus collecting metrics from all nodes
- ✅ Grafana accessible with dashboards
- ✅ Alerts configured and tested (Alertmanager → ntfy)
- ✅ Historical data retained for analysis
- ✅ Loki + Promtail for log aggregation
- ⏳ Renovate for automated updates

### Status: ✅ COMPLETE (Renovate remaining)
### Blog Post: "Monitoring Kubernetes with Prometheus & Grafana"

---

## Fase 7: CI/CD Pipeline (Gitea + Woodpecker CI)

**Goal**: Self-hosted CI/CD pipeline with full control, running on the k3s cluster

### Objectives
- Deploy Gitea as self-hosted Git server on k3s
- Mirror GitHub repos to Gitea
- Deploy Woodpecker CI connected to Gitea
- Build automated pipelines: lint, build, test, deploy
- Complement with GitHub Actions for public repo checks

### Tasks

#### 6.1 Gitea Deployment
Deploy Gitea on k3s via ArgoCD:
- Helm chart or plain manifests in `kubernetes/apps/gitea/`
- Persistent storage via Longhorn
- Ingress at `git.3145.blog` with TLS
- ARM64-compatible image

**Deliverable**: Gitea running and accessible at git.3145.blog

#### 6.2 GitHub Mirror Setup
- Configure Gitea to mirror homelab repo from GitHub (built-in feature)
- Set up mirror schedule (e.g. every 15 min or webhook-triggered)
- Can also push private infra repos directly to Gitea (no GitHub needed)

**Deliverable**: GitHub repos automatically mirrored to Gitea

#### 6.3 Woodpecker CI Deployment
Deploy Woodpecker CI on k3s via ArgoCD:
- Woodpecker server + agent(s) in `kubernetes/apps/woodpecker/`
- Connect to Gitea via OAuth2
- Persistent storage for build logs
- Ingress at `ci.3145.blog` with TLS

**Deliverable**: Woodpecker CI running and connected to Gitea

#### 6.4 Build Pipelines
Create `.woodpecker.yaml` pipelines:

**Pipeline 1: Validate infrastructure**
```yaml
steps:
  - name: lint-yaml
    image: cytopia/yamllint
    commands:
      - yamllint kubernetes/

  - name: validate-manifests
    image: ghcr.io/yannh/kubeconform:latest
    commands:
      - kubeconform kubernetes/
```

**Pipeline 2: Build & Deploy (GitOps)**
```yaml
steps:
  - name: build-image
    image: plugins/docker
    settings:
      repo: registry.3145.blog/myapp
      tags: ${CI_COMMIT_SHA}

  - name: update-manifests
    image: alpine/git
    commands:
      - # Update image tag in k8s manifests
      - # ArgoCD auto-syncs the change
```

**Deliverable**: Automated CI/CD pipeline triggered on push

#### 6.5 GitHub Actions (Complement)
Keep lightweight GitHub Actions for public repo checks:
- Terraform validate on PR
- YAML linting on PR
- These run on GitHub's runners (no self-hosted needed)

Heavy lifting (build, deploy, integration tests) runs on Woodpecker.

**Deliverable**: Dual CI setup — GitHub for public checks, Woodpecker for internal pipeline

### Success Criteria
- ✅ Gitea running on k3s with GitHub mirror
- ✅ Woodpecker CI triggered on push to Gitea
- ✅ Pipeline validates, builds, and deploys automatically
- ✅ ArgoCD picks up changes from pipeline
- ✅ Full self-hosted CI/CD — no dependency on external services

### Blog Post: "Self-Hosted CI/CD with Gitea and Woodpecker on k3s"

---

## Fase 8: Hybrid Cloud (AWS Integration)

**Goal**: Extend homelab to AWS for hybrid setup

### Objectives
- Deploy k3s node on AWS EC2
- Set up VPN mesh with Tailscale
- Distribute workloads across cloud/homelab
- Implement disaster recovery

### Tasks

#### 7.1 Terraform for AWS
Create `terraform/aws/`:
- VPC and subnets
- EC2 instance for k3s node
- Security groups
- S3 bucket for backups

**Deliverable**: AWS infrastructure

#### 7.2 Tailscale VPN Mesh
Connect all nodes:
- Proxmox VMs
- Homelab Pi
- AWS EC2

**Deliverable**: Secure multi-site connectivity

#### 7.3 Cross-Cloud Workload Distribution
Use Kubernetes node affinity:
- Latency-sensitive: homelab
- Burst compute: AWS
- Disaster recovery: AWS

**Deliverable**: True hybrid cloud setup

### Success Criteria
- ✅ k3s node running in AWS
- ✅ All nodes connected via Tailscale
- ✅ Workloads can run in both locations
- ✅ Automated failover tested

### Time Estimate: 2-3 weeks
### Blog Post: "Building a Hybrid Cloud Homelab"

---

## Fase 9: Platform Engineering & Security Hardening

**Goal**: Harden the cluster with policy enforcement, centralized secrets, and a developer portal

### 8.1 Kyverno – Policy Engine (~1 week)

**What**: Kubernetes-native policy engine. Enforces rules as standard YAML manifests — no new languages.

**Why**: Security hardening + portfolio value. Shows you think about compliance and best practices.

**Deploy via ArgoCD** in `kubernetes/infrastructure/kyverno/`:
- Install Kyverno via Helm chart
- Deploy policies as ClusterPolicy resources

**Starter policies:**
- [ ] Require resource limits on all pods
- [ ] Disallow `latest` image tag
- [ ] Require specific labels (app, team)
- [ ] Block privileged containers
- [ ] Enforce read-only root filesystem

**Prerequisites**: ArgoCD (already done)
**Deliverable**: Cluster-wide policy enforcement via GitOps

---

### 8.2 HashiCorp Vault – Secrets Management (~2-3 weeks)

**What**: Centralized secrets management with dynamic credentials, rotation, and audit logging.

**Why**: Replaces SOPS/KSOPS with a more scalable solution. Essential skill for production environments.

**Deploy via ArgoCD** in `kubernetes/infrastructure/vault/`:
- Install Vault via Helm chart (HA mode with integrated storage)
- Configure Kubernetes auth method
- Use External Secrets Operator to sync Vault secrets to K8s Secrets

**Tasks:**
- [ ] Deploy Vault server on k3s
- [ ] Configure auto-unseal (transit or cloud KMS)
- [ ] Set up Kubernetes auth method
- [ ] Deploy External Secrets Operator
- [ ] Migrate Ghost secrets from SOPS to Vault
- [ ] Migrate Vaultwarden secrets from SOPS to Vault
- [ ] Configure audit logging

**Prerequisites**: Running apps (Ghost, Vaultwarden) to integrate with
**Deliverable**: All application secrets managed via Vault

---

### 8.3 Backstage – Developer Portal (~3-4 weeks)

**What**: Spotify's open-source developer portal. Single pane of glass for all services, docs, and infrastructure.

**Why**: Demonstrates platform engineering thinking — highly valued by employers. Ties together everything built so far.

**Deploy via ArgoCD** in `kubernetes/apps/backstage/`:
- Build custom Backstage image with plugins
- PostgreSQL database for catalog
- Ingress at `backstage.3145.blog` with TLS

**Integrations:**
- [ ] ArgoCD plugin – deployment status in Backstage
- [ ] Kubernetes plugin – pod status, logs
- [ ] TechDocs – render existing markdown docs as searchable portal
- [ ] GitHub plugin – link to repositories

**Software Catalog:**
- [ ] Write `catalog-info.yaml` for each service (Ghost, Vaultwarden, Homepage, etc.)
- [ ] Define system/component relationships
- [ ] Create software templates for new services

**Prerequisites**: Vault (for secrets), multiple running services to catalog
**Deliverable**: Developer portal at backstage.3145.blog with full service catalog

---

### Success Criteria
- [ ] Kyverno enforcing policies cluster-wide
- [ ] Vault managing all application secrets
- [ ] Backstage cataloging all services with ArgoCD integration
- [ ] Everything deployed via GitOps

### Blog Post: "From Cluster to Platform: Kyverno, Vault & Backstage"

---

## Future Enhancements

**After core phases:**
- [ ] **Velero GFS-style retention**: Replace single daily schedule with three schedules (daily 14d TTL, weekly 90d TTL, monthly 365d TTL) to mirror PBS grandfather-father-son retention strategy
- [ ] **Renovate**: Automated dependency updates — opens PRs when Helm charts or container images have new versions
- [ ] **Descheduler**: Automatically rebalances pods across nodes when resource usage drifts (fixes the CP-01 84% RAM problem without manual pod deletions)
- [ ] **Trivy Operator**: In-cluster vulnerability scanning of container images and manifests, results visible in Grafana
- [ ] **NetworkPolicies**: Restrict pod-to-pod traffic (namespace isolation)
- [ ] **Tailscale on all k3s nodes**: Install via Ansible so pods can reach Tailscale IPs from any node
- [ ] **Cloudflared GitOps**: Migrate from `--token` to `credentials-file` + local config.yaml
- [ ] Service mesh (Istio/Linkerd)
- [ ] Multi-cluster GitOps
- [ ] Advanced observability (Tempo for tracing)
- [ ] Chaos engineering tests
- [ ] Security scanning (Trivy, Falco)

---

## Metrics for Success

**Technical:**
- ✅ 99%+ uptime for critical services
- ✅ < 5 minute recovery time
- ✅ All infrastructure in code
- ✅ Zero manual deployments

**Professional:**
- ✅ Portfolio-ready documentation
- ✅ Blog series completed
- ✅ Demonstrates modern DevOps practices
- ✅ Shows continuous learning

---

**Last Updated**: 2026-03-19
**Current Phase**: Fase 5 (Ghost & Vaultwarden migration to k3s)
