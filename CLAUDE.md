# Homelab Infrastructure Repository

## Purpose

This repository contains Infrastructure as Code (IaC) and GitOps configurations for Thomas's k3s homelab cluster. It manages everything from VM provisioning to application deployment using modern DevOps practices.

## Directory Structure

```
homelab/
├── terraform/
│   ├── proxmox/          # VM provisioning on Proxmox host
│   │   ├── main.tf       # VM resource definitions (3x control plane VMs)
│   │   ├── providers.tf  # Proxmox provider configuration
│   │   ├── variables.tf  # Input variables
│   │   └── terraform.tfvars  # Variable values (gitignored for secrets)
│   └── aws/              # Future: AWS EC2 worker nodes for hybrid cloud
│
├── ansible/
│   ├── inventory/        # Host definitions and groups
│   ├── playbooks/        # Playbooks for configuration management
│   └── roles/            # Reusable Ansible roles
│
├── kubernetes/
│   ├── bootstrap/        # Initial cluster setup (namespaces, RBAC)
│   ├── infrastructure/   # Core cluster services
│   │   ├── argocd/           # GitOps controller
│   │   ├── cert-manager/     # Certificate management
│   │   ├── longhorn/         # Distributed storage
│   │   ├── metallb/          # Load balancer
│   │   └── ingress-nginx/    # Ingress controller
│   └── apps/             # Application deployments
│       ├── ghost/            # Blog platform (migrating from Media Pi)
│       ├── vaultwarden/      # Password manager (migrating from Media Pi)
│       └── monitoring/       # Prometheus + Grafana stack
│
├── scripts/              # Helper scripts (created as needed)
└── docs/                 # Technical documentation
```

## Infrastructure Components

### Target Architecture

**Control Plane** (3 nodes for HA):
- k3s-cp-01: 192.168.10.21 (VM on Proxmox, 2 CPU, 4GB RAM, AlmaLinux 9)
- k3s-cp-02: 192.168.10.22 (VM on Proxmox, 2 CPU, 4GB RAM, AlmaLinux 9)
- k3s-cp-03: 192.168.10.23 (VM on Proxmox, 2 CPU, 4GB RAM, AlmaLinux 9)

**Worker Nodes**:
- homelab-pi: 192.168.10.11 (Raspberry Pi 5, 8GB RAM, ARM64) - Physical node
- Future: AWS EC2 node for hybrid cloud setup

**Storage**:
- Primary: Longhorn distributed storage across cluster nodes
- Future: NFS from Media Pi (192.168.20.10) for large media files

### Current Status

- ✅ Terraform: Proxmox provider configured, VMs defined
- ⏳ Ansible: Directory structure created, playbooks pending
- ⏳ Kubernetes: Manifests structure created, not yet applied
- 🚧 **Current Focus**: Provisioning k3s control plane VMs with Terraform

## Working with Terraform

### Prerequisites

- Proxmox API token configured in `terraform/proxmox/terraform.tfvars`
- AlmaLinux 9 cloud-init template created on Proxmox (template ID in variables)

### Common Operations

**Initialize Terraform** (first time or after provider changes):
```bash
cd terraform/proxmox
terraform init
```

**Plan changes** (always run before apply):
```bash
terraform plan
```

**Apply changes** (create/modify infrastructure):
```bash
terraform apply
```

**Destroy infrastructure** (use with caution):
```bash
terraform destroy
```

### Important Notes

- **terraform.tfvars**: Contains sensitive values (API tokens, passwords). Never commit to git.
- **State files**: terraform.tfstate contains infrastructure state. Committed for now, but should move to remote backend (Terraform Cloud or S3) in production.
- **VM naming**: Control plane VMs follow pattern `k3s-cp-0X` (01, 02, 03)
- **IP addressing**: Control plane uses 192.168.10.21-23 (hardcoded in main.tf)

## Working with Ansible

### Prerequisites

- SSH access to target hosts (VMs and Raspberry Pi)
- SSH keys configured for passwordless authentication
- Python 3 installed on all target hosts

### Common Operations

**Check connectivity**:
```bash
cd ansible
ansible all -i inventory/hosts.yml -m ping
```

**Run a playbook**:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/playbook-name.yml
```

**Check what would change** (dry-run):
```bash
ansible-playbook -i inventory/hosts.yml playbooks/playbook-name.yml --check
```

### Planned Playbooks

- `k3s-prereqs.yml`: System updates, required packages, kernel tuning
- `k3s-install.yml`: Install k3s on control plane and workers
- `k3s-configure.yml`: Configure k3s cluster settings, join workers

## Working with Kubernetes

### Prerequisites

- k3s cluster running
- kubectl configured with cluster credentials
- ArgoCD installed (for GitOps deployment)

### Deployment Strategy

This repository uses GitOps via ArgoCD:
1. Changes are committed to this repository
2. ArgoCD detects changes and syncs to cluster
3. Manual kubectl commands only for debugging/emergency

### Manual Operations (for debugging)

**Apply a manifest**:
```bash
kubectl apply -f kubernetes/apps/ghost/deployment.yml
```

**Check application status**:
```bash
kubectl get pods -n ghost
kubectl logs -n ghost pod-name
```

**Access ArgoCD UI**:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Access at https://localhost:8080
```

## Coding Standards

### General Principles

- **Minimal & Focused**: Create only what's needed, avoid over-engineering
- **No Premature Abstractions**: Don't create helpers/utilities for one-time operations
- **Comments**: Only where logic isn't self-evident
- **Security First**: No hardcoded secrets, use proper secret management

### Terraform

- Use variables for all configurable values
- Resource names should be descriptive: `k3s_control_plane`, not `vm1`
- Keep modules small and focused
- Always run `terraform fmt` before committing

### Ansible

- Use roles for reusable logic
- Playbooks should be idempotent (safe to run multiple times)
- Tag tasks appropriately for selective execution
- Variable names: lowercase with underscores (`k3s_version`, not `k3sVersion`)

### Kubernetes Manifests

- One resource per file when possible
- File naming: `resource-type.yml` (e.g., `deployment.yml`, `service.yml`)
- Always specify resource requests/limits
- Use namespaces for logical separation
- **ARM64 Compatibility**: Always verify container images support `linux/arm64` platform (for Raspberry Pi)

### Git Workflow

- **Conventional Commits**: Use format `type(scope): description`
  - `feat(terraform): add control plane VMs`
  - `fix(ansible): correct k3s version variable`
  - `docs(kubernetes): update deployment guide`
- **Commit Frequency**: Early and often - small, focused commits
- **Branch Strategy**: Work on main branch (simple project, single developer)

## Migration from Media Pi

Several critical services currently run on Media Pi (Docker) and must be migrated to k3s:

### Critical Services
1. **Ghost** (blog): Priority 1 - public-facing, must minimize downtime
2. **Vaultwarden** (password manager): Priority 1 - critical personal service

### Migration Strategy
1. Build k3s cluster in parallel (don't touch Media Pi yet)
2. Deploy services to k3s cluster (new instances, separate data)
3. Test thoroughly on k3s
4. Plan cutover window (DNS changes, data migration)
5. Migrate one service at a time
6. Keep Media Pi running as backup until stable

### Migration Checklist (per service)
- [ ] Create Kubernetes manifests (Deployment, Service, Ingress)
- [ ] Set up persistent storage (PVC with Longhorn)
- [ ] Configure ingress with TLS (cert-manager + Cloudflare)
- [ ] Test service accessibility
- [ ] Migrate data (databases, files)
- [ ] Update DNS records
- [ ] Monitor for 24-48 hours
- [ ] Document rollback procedure

## Development Workflow

### Typical Development Cycle

1. **Plan**: Understand what needs to change and why
2. **Research**: Check existing patterns in codebase
3. **Implement**: Make minimal changes to achieve goal
4. **Test**: Verify changes work as expected
5. **Commit**: Use conventional commit format
6. **Document**: Update relevant docs if adding new concepts

### When Adding New Features

- Check if similar functionality exists elsewhere in the codebase
- Follow established patterns (naming, structure, tooling)
- Update this CLAUDE.md if introducing new concepts or workflows
- Consider ARM64 compatibility for all containerized workloads

### Before Committing

- [ ] Remove any debug/temporary code
- [ ] Check for accidentally committed secrets
- [ ] Run `terraform fmt` (if changed Terraform files)
- [ ] Update documentation if needed
- [ ] Use conventional commit format

## Troubleshooting

### Terraform Issues

**Problem**: "Error acquiring state lock"
- **Cause**: Previous terraform operation crashed
- **Solution**: `terraform force-unlock LOCK_ID`

**Problem**: "Error creating VM: template not found"
- **Cause**: AlmaLinux template not created or wrong ID
- **Solution**: Check `var.template_id` in terraform.tfvars matches Proxmox template

### Ansible Issues

**Problem**: "Host unreachable"
- **Cause**: SSH not configured or firewall blocking
- **Solution**: Check SSH access manually, verify VLAN connectivity

### Kubernetes Issues

**Problem**: Pods stuck in "Pending"
- **Cause**: No worker nodes or insufficient resources
- **Solution**: `kubectl describe pod <pod-name>` to see why

**Problem**: ImagePullBackOff on ARM64 nodes
- **Cause**: Container image doesn't support ARM64 architecture
- **Solution**: Find ARM64-compatible image or build multi-arch image

## Learning Resources

Since this is a learning project, here are key concepts to understand:

- **Infrastructure as Code**: Terraform manages VMs declaratively
- **Configuration Management**: Ansible ensures consistent system configuration
- **GitOps**: Git as single source of truth, ArgoCD syncs to cluster
- **High Availability**: Multiple control plane nodes prevent single point of failure
- **Cloud-Native Storage**: Longhorn replicates data across nodes
- **Service Mesh**: Future consideration for advanced networking

## Security Considerations

- **Secrets Management**: Never commit secrets to git
  - Use Terraform variables for sensitive values
  - Use Kubernetes Secrets (sealed-secrets or external-secrets later)
- **Network Segmentation**: VLANs isolate homelab traffic
- **TLS Everywhere**: cert-manager + Let's Encrypt for all services
- **Updates**: Regular security updates via Ansible
- **Access Control**: RBAC in Kubernetes, limited Proxmox API permissions

## Future Enhancements

- [ ] Terraform remote state backend (Terraform Cloud or S3)
- [ ] Ansible Vault for secret encryption
- [ ] Sealed Secrets or External Secrets Operator for k8s secrets
- [ ] AWS EC2 worker node for hybrid cloud
- [ ] CI/CD pipeline for automated testing
- [ ] Backup/restore procedures (Velero)

---

**Last Updated**: 2026-02-13
**Maintainer**: Thomas
**Status**: Active Development - Phase 1 (Terraform & Infrastructure)
