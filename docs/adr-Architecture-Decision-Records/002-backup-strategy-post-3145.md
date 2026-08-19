# ADR-002: Backup Strategy after the 3145 decommission

## Status

**Accepted** (2026-08-02) — supersedes [ADR-001](001-backup-strategy.md).

Accepted for **Stage 1** (protect irreplaceable data, no hardware). Stage 2 (capacity for
full VM restore) is deliberately deferred until storage prices normalise — it is a
convenience, not a prerequisite.

## Context

### What happened

ADR-001 defined a 3-2-1 strategy in which **every** backup target was hosted on "Media Pi"
— the Raspberry Pi 5 `3145`. It was the Garage replication target, the PBS datastore, and
the single consolidation point that pushed everything off-site to Cloudflare R2.

`3145` was decommissioned in 2026-05. Nothing replaced it. The entire backup pipeline went
with the hardware, and the documentation was never updated.

### Verified current state (2026-08-02)

| Component | ADR-001 said | Reality |
|-----------|--------------|---------|
| Longhorn | Deployed | ✅ Deployed (`argocd/applications/longhorn.yaml`) — but this is *live storage*, not backup |
| Garage (S3) | On Media Pi | ❌ Gone — no manifests anywhere in `kubernetes/` |
| Velero | In cluster → Garage | ❌ Gone — no ArgoCD Application |
| PBS | On Media Pi | ❌ Gone. Ansible role exists (`ansible/roles/pbs/`) but no VM is defined in `terraform/proxmox/main.tf` |
| Cloudflare R2 | Off-site copy | ❌ No process feeds it |
| Media Pi | Consolidation point | ❌ Decommissioned 2026-05 |

**There is currently no backup of any workload, VM, or volume.**

`docs/roadmap.md` still marks Fase 4 as "✅ COMPLETE" with "3-2-1 backup strategy fully
operational". That is false and has been corrected as part of this ADR.

### Why this is urgent

ADR-001's core argument was that Ghost and Vaultwarden must not be migrated to k3s until
backups exist. Both are now running in k3s (`argocd/applications/ghost.yaml`,
`vaultwarden.yaml`) — the migration happened under a safety net that has since been removed.
Vaultwarden is a password manager; losing its Longhorn volume means losing the vault.

Longhorn's replicas are **not** a backup. They protect against a node failing, not against
deletion, corruption, ransomware, or a bad `kubectl` command — all replicas apply the same
write.

## Decision

Split backup by **what the data is worth**, not by what the infrastructure looks like.
ADR-001's mistake was treating all data as equally precious, which made the whole strategy
depend on a large consolidation host — and collapse when that host was retired.

### The insight: most of this data does not need backing up

| Data | Size | Backup needed? |
|------|------|----------------|
| k3s VMs (6 × 50 GB) | ~300 GB | ❌ No — fully reproducible from Terraform + Ansible + ArgoCD |
| Media (arr-stack) | 500 GB | ❌ No — re-acquirable; annoying to lose, not a disaster |
| Proxmox host config | MB | ✅ Yes, but it is text files |
| **Ghost volume** (blog posts) | few GB | ✅ **Irreplaceable** |
| **Vaultwarden volume** (vault) | ~100 MB | ✅ **Irreplaceable** |

Genuinely irreplaceable data totals **under 10 GB**. This is the whole point of an
IaC homelab: the effort already spent making infrastructure reproducible means backing up
VM images is paying twice for the same guarantee.

### Stage 1 — protect the irreplaceable (now, ~0 kr)

Scheduled push of the Ghost and Vaultwarden Longhorn volumes, plus Proxmox host config, to
**Cloudflare R2**. Under 10 GB fits R2's free tier; egress is free, and Object Lock gives
immutability against ransomware and credential compromise.

No disk, no PBS VM, no rack space, no hardware dependency. This is the entire critical path
and it can ship this week.

### Stage 2 — capacity for fast full restore (deferred)

A local disk large enough for full VM/LXC images via PBS, giving fast bare-metal recovery
rather than rebuilding from IaC. Deferred: storage prices are currently inflated, and
Stage 1 removes the urgency. Revisit when prices normalise.

When it happens, the constraint from ADR-001 still holds: **the backup target must not live
inside the Proxmox cluster it protects.** Options ranked by cost were a USB 3.5" desktop
drive on pve3 (~1 500–2 200 kr, must be self-powered — bus-powered 2.5" drives drop the USB
link under sustained PBS writes), a dedicated fourth node, or a NAS. A NAS would also solve
bulk media storage and finally use the switch's two idle 10G SFP+ ports, but none of that is
urgent.

The existing `ansible/roles/pbs/` role is reusable at that point, but its default
(`pbs_datastore_disk: /dev/vdb`, a virtio disk from Terraform) would place backups on the
same `vmdata` pool as the source VMs and must be changed.

Velero for granular k8s restore also belongs to Stage 2. Stage 1 protects the same data with
far less machinery; Velero's value is operational convenience across all namespaces, not
protection of the two volumes that actually matter.

## Alternatives Considered

**Do nothing / accept the risk.** Rejected. Vaultwarden and Ghost hold data that cannot be
regenerated.

**Longhorn replicas as backup.** Rejected — see above. Replication is not backup.

**Backup straight to R2 with no local copy.** Cheapest, no hardware. Rejected as the primary
plan because restore of a full VM image over a home uplink is slow enough to matter during an
actual outage, and it drops 3-2-1 to 2-1-1. Reasonable as a *stopgap* for Vaultwarden's
volume specifically until hardware exists — that is a small dataset where the trade-off flips.

**Rebuild Garage exactly as ADR-001 described.** Rejected. Garage on a single Pi was chosen
when `3145` was the natural host. With that host gone there is no reason to run a second
object store when PBS can sync to R2 directly.

## Consequences

### Positive
- Two independent restore paths again (full VM via PBS, granular app via Velero)
- No single consolidation host — removes the failure mode that made ADR-001 collapse when one
  machine was retired
- Documentation stops claiming protection that does not exist

### Negative
- Until Stage 2, recovering a lost Proxmox node means rebuilding from IaC rather than
  restoring an image — correct, but slower and only as good as the IaC actually is
- Restore-from-IaC is now a load-bearing assumption. It must be **tested**, not assumed;
  an untested rebuild path is not meaningfully better than an untested backup
- Media (500 GB) is explicitly unprotected. Accepted deliberately

### Open questions
1. R2 credentials and token rotation are still unresolved from ADR-001
   (`docs/runbooks/pbs-setup.md`)
2. Where should the Stage 1 job run? It must not depend on the cluster it backs up
3. When to schedule the first restore drill — the assumption above needs proving
