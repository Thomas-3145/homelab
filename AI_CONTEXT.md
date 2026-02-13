# AI Context: K3s Homelab Infrastructure

> **Purpose**: Operational guidelines for AI assistants working with this homelab infrastructure.
> For general project context, see [CLAUDE.md](./CLAUDE.md).

## Current Infrastructure Status

**Phase**: 🚧 Building k3s cluster (VMs not yet provisioned)

**Proxmox Host**: HP EliteDesk 800 G4 (192.168.10.20)
- i5-8500T, 32GB RAM, 1.2TB storage
- Runs: Control plane VMs (Ubuntu Server)

**Physical Nodes**:
- Homelab Pi (192.168.10.11): Raspberry Pi 5, 8GB RAM, 256GB NVMe - **ARM64**
- Media Pi (192.168.20.10): Raspberry Pi 5, 8GB RAM, 512GB NVMe - Docker host (temporary)

**Planned k3s Cluster** (Not yet deployed):
```
Control Plane (HA):
├─ k3s-cp-01: 192.168.10.21 (VM, 2 CPU, 4GB RAM, Ubuntu Server) - amd64
├─ k3s-cp-02: 192.168.10.22 (VM, 2 CPU, 4GB RAM, Ubuntu Server) - amd64
└─ k3s-cp-03: 192.168.10.23 (VM, 2 CPU, 4GB RAM, Ubuntu Server) - amd64

Workers:
├─ homelab-pi: 192.168.10.11 (Physical, ARM64) - Raspberry Pi 5
└─ aws-worker: TBD (Future hybrid cloud expansion)
```

## Technology Stack

| Component | Technology | Status |
|-----------|-----------|--------|
| VM Provisioning | Terraform + Proxmox | 🚧 Configured, not applied |
| Configuration | Ansible | ⏳ Planned |
| Orchestration | k3s | ⏳ Planned |
| GitOps | ArgoCD | ⏳ Planned |
| Storage | Longhorn | ⏳ Planned |
| Ingress | ingress-nginx | ⏳ Planned |
| Load Balancer | MetalLB | ⏳ Planned |
| Certificates | cert-manager + Cloudflare | ⏳ Planned |
| Monitoring | Prometheus + Grafana | ⏳ Planned |

## Critical Operational Guidelines

### 1. Architecture Compatibility (CRITICAL!)

**ARM64 Safety Rules**:
- ⚠️ Homelab Pi is **ARM64** - cannot run x86-only containers
- ✅ **ALWAYS** verify Docker images support `linux/arm64` before suggesting
- ✅ Check Docker Hub → "OS/ARCH" tab or manifest list
- ✅ If x86-only, add `nodeSelector: {kubernetes.io/arch: amd64}` to deployment

**Example - Safe Deployment**:
```yaml
spec:
  template:
    spec:
      nodeSelector:
        kubernetes.io/arch: amd64  # Explicit x86 scheduling
      containers:
      - name: app
        image: some-x86-only-image:latest
```

### 2. Storage Guidelines

- **Persistent Storage**: Use `longhorn` StorageClass (once deployed)
- **Temporary**: Use `emptyDir` for ephemeral data
- **Avoid**: `hostPath` unless absolutely necessary (hardware access)
- **Future**: NFS from Media Pi for large media files

**Example PVC**:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
spec:
  storageClassName: longhorn
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 10Gi
```

### 3. Network & Ingress

- **VLANs**: Homelab on VLAN 10 (192.168.10.0/24), Media on VLAN 20
- **Ingress**: Will use ingress-nginx + cert-manager (Let's Encrypt via Cloudflare)
- **Load Balancer**: MetalLB in Layer 2 mode (IP pool from VLAN 10)
- **DNS**: Managed via Cloudflare

### 4. Service Migration from Media Pi

**Critical Services to Migrate**:
1. **Ghost** (blog) - CRITICAL, public-facing
2. **Vaultwarden** (password manager) - CRITICAL, personal service

**Migration Strategy**:
- ✅ Build k3s cluster in parallel (don't touch Media Pi yet)
- ✅ Deploy new instances on k3s with separate data
- ✅ Test thoroughly before cutover
- ✅ Migrate one service at a time
- ✅ Keep Media Pi as backup until stable

**When suggesting migrations**:
- Always include PVC for data persistence
- Plan for database/data migration steps
- Configure TLS/certificates from the start
- Test rollback procedures

### 5. Development Best Practices

**Terraform**:
- Always `terraform plan` before `apply`
- Never commit `terraform.tfvars` (contains secrets)
- Use variables for all configurable values

**Kubernetes Manifests**:
- Prefer declarative YAML over imperative commands
- Always specify resource requests/limits
- Use namespaces for logical separation
- Validate with `kubectl apply --dry-run=client -o yaml`

**Git Commits**:
- Use conventional commits: `feat(terraform): description`
- Commit early and often
- Never commit secrets or sensitive data

### 6. Security Considerations

- **Secrets**: Never hardcode in manifests (use Kubernetes Secrets, future: Sealed Secrets)
- **Network**: Already segmented via VLANs
- **TLS**: cert-manager will handle all certificates automatically
- **Updates**: Regular security updates via Ansible

## Current Development Focus

**Now**: Provisioning k3s control plane VMs with Terraform
**Next**:
1. Apply Terraform to create VMs
2. Develop Ansible playbooks for k3s installation
3. Bootstrap k3s cluster
4. Install ArgoCD for GitOps
5. Deploy core infrastructure services

## Quick Reference Commands

**Terraform** (from `terraform/proxmox/`):
```bash
terraform init          # Initialize
terraform plan          # Preview changes
terraform apply         # Create infrastructure
terraform destroy       # Delete infrastructure (use with caution!)
```

**Ansible** (from `ansible/`):
```bash
ansible all -i inventory/hosts.yml -m ping  # Test connectivity
ansible-playbook -i inventory/hosts.yml playbooks/name.yml  # Run playbook
ansible-playbook ... --check  # Dry-run mode
```

**Kubernetes** (once cluster is running):
```bash
kubectl get nodes       # Check cluster nodes
kubectl get pods -A     # All pods in all namespaces
kubectl logs -n namespace pod-name  # View logs
kubectl apply -f file.yml  # Deploy manifest
```

---

**Last Updated**: 2026-02-14
**Status**: Pre-deployment (building infrastructure)
