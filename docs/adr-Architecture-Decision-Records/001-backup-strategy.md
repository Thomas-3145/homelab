# ADR-001: Backup Strategy (3-2-1 with Velero + Garage + PBS)

## Status

Accepted

## Context

The homelab runs critical services — Ghost (blog) and Vaultwarden (password manager) — that need reliable backups before being migrated from the Media Pi (Docker) to the k3s cluster.

The original roadmap had app migration (Phase 3) before backups (Phase 4). This was reversed after realizing the risk: migrating Ghost and Vaultwarden to k3s without a backup solution in place means any cluster issue could result in data loss. The safer approach is to have Longhorn, Garage, and Velero fully operational before moving production workloads.

### MinIO → Garage

MinIO was the initial choice for S3-compatible object storage. It was dropped for two reasons:

1. **Licensing**: MinIO moved away from open source and now targets enterprise customers. Not suitable for a homelab project.
2. **Resource usage**: Garage is significantly lighter on resources, which matters when running on a Raspberry Pi 5 (8GB RAM) alongside other workloads.

### Velero CSI requirement

A key discovery during planning: Velero without the Longhorn CSI plugin (`velero-plugin-for-csi`) only backs up Kubernetes manifests (Deployments, Services, ConfigMaps, etc.) — **not** the actual data in persistent volumes. This means a restore would recreate all the pods but with empty disks. Both the CSI plugin and Longhorn configured as a CSI snapshot provider are required for complete backups.

## Decision

Implement a 3-2-1 backup strategy with two independent backup paths:

**Application backup (k3s workloads):**
Velero with CSI snapshots → Garage (S3) on 3145 Pi → Cloudflare R2 (off-site)

**System backup (Proxmox VMs):**
Proxmox VM backup → PBS on 3145 Pi → Cloudflare R2 (off-site)

> **Note**: Originally designed for two Raspberry Pi 5:s (homelab-pi + media-pi).
> Homelab Pi was sold 2026-03-22. All backup functions consolidated on a single Pi (3145, 192.168.20.10).

### Architecture

```
┌──────────────────────────────────────────────────────────┐
│                     k3s Cluster                          │
│                                                          │
│   ┌──────────┐     ┌────────┐     ┌─────────────────┐    │
│   │ Longhorn │────►│ Velero │────►│ Garage (S3)     │    │
│   │ (volymer)│ CSI │        │ S3  │ Homelab Pi 3145 │    │
│   └──────────┘snap └────────┘push └────────┬────────┘    │
│                                            │             │
└────────────────────────────────────────────┼─────────────┘
                                             │
                                          S3 sync
                                             │
┌────────────────────────────┐               │
│ Proxmox (The Beast)        │               │
│                            │               │
│  ┌──────┐┌──────┐┌──────┐  │               │
│  │CP-01 ││CP-02 ││CP-03 │  │               │
│  └──────┘└──────┘└──────┘  │               │
│                            │               │
└─────────────┬──────────────┘               │
              │                              │
         VM backup                           │
              │                              │
              ▼                              ▼
┌──────────────────────────────────────────────────────────┐
│                 Media Pi (2TB SSD)                       │
│                 Consolidation point                      │
│                                                          │
│   ┌───────────────────┐   ┌───────────────────────────┐  │
│   │ PBS               │   │ Garage copy               │  │
│   │ VM backups ~40GB  │   │ App backups ~10-20GB      │  │
│   └─────────┬─────────┘   └─────────────┬─────────────┘  │
│             │                           │                │
│             └─────────┬─────────────────┘                │
│                       │                                  │
└───────────────────────┼──────────────────────────────────┘
                        │
                     S3 sync
                        │
                        ▼
┌──────────────────────────────────────────────────────────┐
│              Cloudflare R2 (off-site)                    │
│              Immutable backups (Object Lock)             │
│              VM images + App data                        │
└──────────────────────────────────────────────────────────┘
```

Media Pi acts as the single consolidation point. All backups — both app data and VM images — flow through Media Pi before being synced to R2. This simplifies off-site sync to a single process from one machine.

### Copy distribution

| Data type | Copy 1 (live) | Copy 2 (local backup) | Off-site |
|-----------|---------------|----------------------|----------|
| App data (Velero) | k3s cluster (Longhorn) | 3145 Pi (Garage S3) | Cloudflare R2 |
| VM images | Proxmox (pve1/pve2) | 3145 Pi (PBS) | Cloudflare R2 |

### Implementation order

Longhorn → Garage → Velero → **then** Ghost/Vaultwarden migration. Backups before apps.

### Off-site: Cloudflare R2

- No egress fees (unlike AWS S3)
- S3-compatible API
- Already have a Cloudflare account (domain management)
- Object Lock support — immutable backups protect against ransomware and accidental deletion

### Schedule

All backups run at 04:00 to avoid overlap with production workloads.

## Alternatives Considered

### MinIO instead of Garage
Original choice. Dropped due to MinIO's shift away from open source toward enterprise licensing, and higher resource requirements. Garage is lightweight, S3-compatible, and a better fit for homelab scale.

### Restic/Borg (direct backup tools)
Considered early on. These are solid general-purpose backup tools, but Velero is purpose-built for Kubernetes: it understands namespaces, labels, CRDs, and integrates with CSI for volume snapshots. Restic would require custom scripting to achieve the same Kubernetes-aware backups.

### NFS-based backups
Simpler but less flexible. S3 via Garage gives Velero a native target and enables future replication to R2 without changing the backup pipeline.

### Backups after app migration (original roadmap order)
The roadmap had Phase 3 (apps) before Phase 4 (backups). Reversed because migrating production services without backup infrastructure is an unnecessary risk. If something breaks during migration, there's no way to recover.

## Consequences

### Positive
- Ghost and Vaultwarden can be migrated to k3s with confidence — backups are already in place
- Two independent restore paths: full VM restore (PBS) or granular app restore (Velero)
- Off-site copy (R2) protects against physical disasters
- Object Lock on R2 protects against ransomware and compromised credentials
- Single consolidation point (Media Pi) simplifies off-site sync — one machine, one process to R2

### Negative
- More components to set up before app migration can begin (Longhorn, Garage, Velero)
- Garage and Velero add complexity to the cluster
- Media Pi is a single point for consolidated backups (mitigated by R2 off-site)
- R2 replication is a future task — until then, off-site protection is not in place
