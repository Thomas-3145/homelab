# Infrastructure Plan: Adding Lenovo ThinkCentre

> **Status: ARCHIVED (2026-04).** The Lenovo M75q (planned as `pve2`) was sold
> in April 2026 and never went into production. The cluster ended up running
> on `pve1` (HP EliteDesk G4) and `pve3` (HP EliteDesk G8) instead. This
> document is preserved for historical context only — the layout, hostnames
> and storage decisions described below are obsolete.
>
> Original planning date: 2026-03-22.

## Hardware Overview

| Node | Hardware | RAM | Storage | Role |
|------|----------|-----|---------|------|
| **HP EliteDesk** | i5-8500T | 32 GB | 1.2 TB | Proxmox host #1 |
| **Lenovo ThinkCentre** | Ryzen 5 Pro 3400GE | 64 GB | 2 TB | Proxmox host #2 (NEW) |
| **Media Pi** | Raspberry Pi 5 | 8 GB | 512 GB NVMe | Backup, monitoring, IoT |

## Planned Node Distribution

### Proxmox VMs (k3s cluster)

| VM | Physical Host | Purpose |
|----|--------------|---------|
| k3s-cp-01 | HP | Control plane |
| k3s-cp-02 | Lenovo | Control plane |
| k3s-cp-03 | Lenovo | Control plane |
| k3s-worker-01 | Lenovo | k3s workloads |
| k3s-worker-02 | HP | k3s workloads |
| **media-vm** | **Lenovo** | **Jellyfin + arr-stack (standalone, NOT in k3s)** |

**HA note**: CP nodes spread across two physical hosts — survives a single host failure.

### Media VM on Lenovo (standalone — NOT in k3s)

Run Jellyfin + arr-stack as a **standalone Proxmox VM with Docker Compose**, separate from the k3s cluster.

**Why outside k3s:**
- GPU passthrough for transcoding is painful in k8s (device plugins, node affinity, scheduling)
- Arr-stack (Sonarr/Radarr/Prowlarr/qBittorrent) is stateful and talks heavily between services — Docker Compose handles this trivially, k8s adds complexity with no benefit
- No reason for Longhorn to replicate media files (they can be re-downloaded)
- If the k3s cluster goes down, you still want to be able to stream
- PBS backs up this VM like any other — simple and reliable

**Why VM over LXC:**
- Docker Compose works out of the box — no privileged LXC hacks needed
- GPU passthrough is simpler and better documented in VMs
- Better isolation from the host
- With 64 GB RAM, the VM overhead is negligible

**HW transcoding note**: The Ryzen 5 Pro 3400GE has AMD VCN (not Intel Quick Sync).
Jellyfin supports VAAPI for AMD GPUs — pass `/dev/dri` into the VM and enable VAAPI in Jellyfin settings.

**Storage layout inside VM:**
```
/data/
├── downloads/      # qBittorrent incomplete + complete
├── movies/         # Radarr → Jellyfin
└── tv/             # Sonarr → Jellyfin
```
All containers share the same `/data` mount in Docker Compose — this enables **hardlinks** so Sonarr/Radarr can "move" files instantly without copying. See [TRaSH Guides](https://trash-guides.info/) for optimal arr-stack setup.

**Backup policy**: Only back up VM config + arr-stack databases (via PBS). Media files are NOT backed up — they can be re-downloaded. Exclude `/data/downloads/`, `/data/movies/`, `/data/tv/` from PBS or use a separate non-backed-up disk for media.

### Media Pi

| Service | Purpose | Resource Impact |
|---------|---------|----------------|
| PBS | VM backups from both Proxmox hosts | Moderate (dedup is CPU-heavy during backup windows) |
| Garage | S3-compatible storage (Velero target) | Light |
| Uptime Kuma | Monitoring/uptime checks | Very light |
| ntfy | Push notifications (Alertmanager target) | Very light |
| IoT services | TBD (Home Assistant, Zigbee, etc.) | Varies |

## Storage Concern: 512 GB SSD on Pi

Current estimate:
- PBS: 3 CP VMs + 2 worker VMs. ~160 GB raw disk, but PBS deduplication brings this down to ~40-80 GB for nightly incrementals
- Garage/Velero: k8s manifests + PV snapshots, ~10-20 GB depending on app data
- **Total: ~50-100 GB**, leaving ~400 GB free

This works for now, but will grow as more apps and VMs are added. Monitor usage and consider upgrading to a larger SSD if it approaches 70% utilization. Backups are also forwarded to Cloudflare R2, so the Pi is a transit node, not the sole copy.

## Backup Architecture (3-2-1)

```
Layer 3 — VM backups
  Proxmox (HP + Lenovo) → PBS (Media Pi) → local 512 GB SSD
  Protects: VM disk images (full OS + k3s node state)

Layer 2 — Kubernetes backups
  Velero (in k3s) → Garage (Media Pi) → Cloudflare R2
  Protects: k8s resources (deployments, secrets, configmaps) + Longhorn PV snapshots

Layer 1 — Live storage (NOT backup, this is HA)
  Longhorn replicates PVs across k3s nodes in real-time
  Protects against: single node failure (pod reschedules to surviving node)
```

**How they complement each other:**
- Longhorn keeps services running if a node dies (availability)
- Velero restores apps + data if the cluster breaks (disaster recovery)
- PBS restores entire VMs if Proxmox breaks (bare-metal recovery)
- R2 is the off-site copy (house-fire scenario)

## Longhorn Considerations

With 5 k3s nodes across 2 physical hosts:
- Set `numberOfReplicas: 2` minimum — ensures data survives a single host failure
- Longhorn stores replicas on each node's local disk (managed by Longhorn, not manually)
- CP nodes can also hold Longhorn replicas (they do by default)
- Monitor disk pressure — especially on HP (1.2 TB shared with VMs)

## Network / VLAN Note

Currently planned: Media Pi on the **media VLAN** (192.168.20.0/24) running both backup services and IoT.

**Known trade-off**: IoT devices on the same L2 segment as backup services is not ideal from a security perspective. A compromised IoT device could see backup traffic.

**Mitigating factors:**
- PBS and Garage only accept inbound connections (they don't initiate)
- Backup data transits to R2 quickly — Pi is not long-term storage
- IoT devices are low-risk in a homelab context

**Future improvement**: Create a dedicated backup VLAN using a VLAN tag on the Pi's eth0 interface. The Pi can have two VLAN interfaces on a single physical port — one for IoT, one for backups. This costs nothing extra (just router + Pi configuration).

## TODO Before Implementation

- [ ] Install Proxmox on Lenovo
- [ ] Configure Terraform for new Proxmox host (add provider + VM definitions)
- [ ] Provision new CP + worker VMs
- [ ] Join new nodes to existing k3s cluster (Ansible)
- [ ] Set up media VM with Docker Compose (Jellyfin + arr-stack)
- [ ] Configure AMD VAAPI transcoding in Jellyfin
- [ ] Verify Longhorn replicates across both physical hosts
- [ ] Migrate PBS + Garage to Media Pi (if not already there)
- [ ] Update Velero to point Garage at Pi's new location (if moved)
- [ ] Consider backup VLAN tag on Pi's eth0


Garage PV → Lenovo — uppdatera pv.yaml nodeAffinity när Lenovo är på plats
