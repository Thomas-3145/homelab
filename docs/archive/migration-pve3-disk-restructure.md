# Migration Guide: pve3 + Disk Restructure

> **Status: ARCHIVED (2026-04).** This plan was written when the cluster was
> expected to run pve1 + pve2 (Lenovo M75q) + pve3. The Lenovo was sold before
> being put into production, so the final cluster ended up as **pve1 + pve3
> only** (no pve2). The pve1 disk restructure (Phase 1) and pve3 install
> (Phase 2) were carried out — the pve2-related steps (RAM swap, Phase 3,
> worker-03 on pve3) were not. Preserved for historical context.
>
> Original planning date: 2026-04-07.

## Target State

### Hardware

| Host | Model | RAM | NVMe 1 (boot) | NVMe 2 (data) | VLAN 10 IP |
|------|-------|-----|----------------|----------------|------------|
| **pve1** | HP EliteDesk (existing) | 32 GB (2667 MT/s after swap) | 256 GB → Proxmox OS | 1 TB → `nvme-k3s` | .10.20 |
| **pve2** | Lenovo M75q | 32 GB (3200 MT/s after swap) | 1 TB → Proxmox + allt | — (1 slot) | .10.30 |
| **pve3** | HP EliteDesk 800 G8 | 64 GB (from pve2) | 256 GB → Proxmox OS | 2 TB → `nvme-k3s` | .10.40 |
| **3145** | RPi5 | 8 GB | 512 GB | — | VLAN 20, .20.10 |

### k3s Cluster — 1 CP + 1 Worker per Host

| Host | Control Plane | Worker |
|------|---------------|--------|
| pve1 | k3s-cp-01 (.10.21) | k3s-worker-01 (.10.52) |
| pve2 | k3s-cp-02 (.10.22) | k3s-worker-02 (.10.53) |
| pve3 | k3s-cp-03 (.10.23) | k3s-worker-03 (.10.54) |

### Additional VMs/LXCs

| VM/LXC | Host | Datastore | Notes |
|--------|------|-----------|-------|
| Jellyfin LXC | pve3 | nvme-k3s (2 TB) | Intel UHD 730, /dev/dri passthrough |
| gitlab-runner | pve2 or pve3 | local-lvm | Decide later |
| Media storage | pve3 | nvme-k3s (2 TB) | ~1.5 TB available, bind-mount into Jellyfin LXC |

### 3145 (RPi5) — Standalone Backup Node

| Service | Status |
|---------|--------|
| PBS | Keep |
| Garage | Move here from k3s cluster |
| Uptime Kuma | Keep |
| ntfy | Keep |
| QDevice | Remove (3 Proxmox nodes = automatic quorum) |

---

## Phase 1: Restructure pve1 (can start immediately)

pve1 currently has Proxmox + all VMs on a single 1 TB NVMe. Goal: move Proxmox OS
to the 256 GB NVMe, use the 1 TB exclusively for VM data.

### Prerequisites

- [ ] Verify PBS backups are current for all pve1 VMs
- [ ] Note all VMIDs on pve1: `qm list` on pve1
- [ ] Verify pve2 has enough free RAM and disk for temporary VM hosting

Expected VMs on pve1: k3s-cp-01, k3s-worker-01 (2 VMs, 12 GB RAM total).
pve2 has 64 GB RAM and ~900 GB disk — plenty of room temporarily.

### Step 1.1: Backup everything

```bash
# SSH into pve1
ssh -p 22456 root@pve1.taild78f1d.ts.net

# List all VMs
qm list

# Create a manual backup of each VM (replace VMID)
vzdump <VMID> --storage local --compress zstd --mode snapshot
```

Alternatively, verify that the latest PBS backup for each VM is recent:
check PBS web UI at https://3145:8007.

### Step 1.2: Migrate VMs from pve1 → pve2

This can be done from the Proxmox web GUI (easiest) or CLI.

**GUI method:**
1. Go to pve1 in the Proxmox web UI
2. Right-click each VM → Migrate
3. Target node: pve2
4. Target storage: local-lvm (on pve2)
5. The VM will be shut down, migrated, and can be started on pve2

**CLI method:**
```bash
# From pve1 — for each VM (offline migration with storage move)
qm migrate <VMID> pve2 --targetstorage local-lvm --online 0
```

After migration, verify all VMs are running on pve2:
```bash
# On pve2
qm list
```

Verify k3s cluster health:
```bash
# From your local machine
kubectl get nodes -o wide
```

All 5 nodes should be Ready (they keep their IPs regardless of which Proxmox host
they run on).

### Step 1.3: Remove pve1 from Proxmox cluster (temporarily)

Before reinstalling, cleanly remove pve1 from the cluster to avoid quorum issues.

```bash
# On pve2 — remove pve1 from cluster
pvecm delnode pve1
```

### Step 1.4: Physical work in pve1 (disks + RAM swap with pve2)

pve1 is shut down after VM migration. This is the time to do all physical changes.

**Disk:**
1. Shut down pve1
2. The machine has 2 NVMe slots — identify which is which
3. Current: 1 TB is the boot disk. The 256 GB should be the second slot.
4. You do NOT need to physically move them — just install Proxmox on the 256 GB disk
   in the next step (select the correct disk during installation)
5. Apply 50×50 mm thermal pad (1 mm) on NVMe drives that need it — check for
   existing pads and replace if worn, or add where bare contact to heatsink/chassis

**RAM swap (pve1 ↔ pve2):**

pve1 currently has 2× 16 GB DDR4 rated at 3200 MT/s, but the CPU only runs them
at 2667 MT/s — wasted potential. pve2's CPU supports 3200 MT/s. Swap the sticks
so each machine runs at its CPU's max speed.

1. Remove 2× 16 GB (3200 MT/s) from pve1, set aside
2. Shut down pve2
3. Remove 2× 16 GB (2667 MT/s) from pve2
4. Install pve1's sticks (3200 MT/s) into pve2 → pve2 now runs at full 3200 MT/s
5. Install pve2's sticks (2667 MT/s) into pve1 → matches pve1's CPU max
6. Start pve2 first, verify RAM: `free -h` and `dmidecode -t memory | grep Speed`
7. Both machines still have 32 GB — only the speed changes

### Step 1.5: Reinstall Proxmox on 256 GB NVMe

1. Boot from Proxmox USB installer
2. **Important**: When choosing the installation disk, select the **256 GB NVMe**
   (not the 1 TB!)
3. Set hostname: `pve1`
4. Set IP: `192.168.10.20/24`, gateway `192.168.10.1`
5. Complete installation, reboot

### Step 1.6: Set up the 1 TB NVMe as a separate datastore

After Proxmox is installed on the 256 GB, the 1 TB disk still has old data.
Wipe it and create a clean datastore.

```bash
# SSH into the fresh pve1
ssh -p 22456 root@192.168.10.20

# Identify the 1 TB disk (likely /dev/nvme0n1 or /dev/nvme1n1)
lsblk

# Wipe the old partition table
wipefs -a /dev/nvmeXn1    # replace X with correct device

# Option A: LVM thin pool (recommended — same as local-lvm, Proxmox native)
pvcreate /dev/nvmeXn1
vgcreate nvme-k3s /dev/nvmeXn1
lvcreate -l 100%FREE -T nvme-k3s/data

# Add as storage in Proxmox
pvesm add lvmthin nvme-k3s --vgname nvme-k3s --thinpool data --content rootdir,images
```

Verify in the Proxmox GUI: Datacenter → Storage — you should see `nvme-k3s` listed.

### Step 1.7: Rejoin the Proxmox cluster

```bash
# On fresh pve1
pvecm add 192.168.10.30   # join via pve2
```

### Step 1.8: Create cloud-init template on pve1

The old template (9000) was on the wiped disk. Create a new one on nvme-k3s.

```bash
# Download Ubuntu cloud image
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

# Create VM from image
qm create 9000 --memory 2048 --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci
qm set 9000 --virtio0 nvme-k3s:0,import-from=/root/jammy-server-cloudimg-amd64.img
qm set 9000 --ide2 nvme-k3s:cloudinit
qm set 9000 --boot order=virtio0
qm set 9000 --serial0 socket --vga serial0
qm template 9000

# Clean up
rm jammy-server-cloudimg-amd64.img
```

### Step 1.9: Migrate VMs back to pve1

```bash
# From pve2 CLI or GUI — migrate back to pve1, targeting the new datastore
qm migrate <VMID> pve1 --targetstorage nvme-k3s --online 0
```

Start VMs on pve1 and verify k3s:
```bash
kubectl get nodes -o wide
```

### Step 1.10: Post-migration checks

- [ ] All k3s nodes are Ready
- [ ] Longhorn volumes are healthy: check Longhorn UI or `kubectl get volumes -n longhorn-system`
- [ ] ArgoCD apps are synced: `kubectl get app -n argocd`
- [ ] PBS can still back up pve1 VMs

### Step 1.11: Apply standard hardening

Run Ansible to re-apply SSH hardening, Tailscale, etc. on the fresh pve1:

```bash
cd ~/dev/3145/homelab
ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/site.yaml --limit pve1
```

---

## Phase 2: Set up pve3 (when hardware is ready)

### Prerequisites

- [ ] pve3 hardware is working with power supply
- [ ] 256 GB NVMe + 2 TB NVMe installed
- [ ] Network cable connected to 2.5G port on router
- [ ] Router configured: static IP 192.168.10.40 for pve3's MAC address (VLAN 10)

### Step 2.1: Install Proxmox on 256 GB NVMe

1. Boot from Proxmox USB installer
2. Select the **256 GB NVMe** as installation disk
3. Hostname: `pve3`
4. IP: `192.168.10.40/24`, gateway `192.168.10.1`
5. Complete installation, reboot

### Step 2.2: Set up 2 TB NVMe as datastore

```bash
ssh -p 22456 root@192.168.10.40

lsblk  # identify the 2 TB disk

wipefs -a /dev/nvmeXn1
pvcreate /dev/nvmeXn1
vgcreate nvme-k3s /dev/nvmeXn1
lvcreate -l 100%FREE -T nvme-k3s/data

pvesm add lvmthin nvme-k3s --vgname nvme-k3s --thinpool data --content rootdir,images
```

### Step 2.3: Join Proxmox cluster

```bash
pvecm add 192.168.10.20   # join via pve1
```

After this you have 3 Proxmox nodes — quorum is automatic (3 votes, quorum = 2).

### Step 2.4: Remove QDevice from 3145

QDevice is no longer needed with 3 nodes.

```bash
# On pve1 or pve2
pvecm qdevice remove
```

On 3145, you can uninstall the corosync-qdevice packages if you want to clean up.

### Step 2.5: Create cloud-init template on pve3

```bash
# On pve3
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

qm create 9002 --memory 2048 --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci
qm set 9002 --virtio0 nvme-k3s:0,import-from=/root/jammy-server-cloudimg-amd64.img
qm set 9002 --ide2 nvme-k3s:cloudinit
qm set 9002 --boot order=virtio0
qm set 9002 --serial0 socket --vga serial0
qm template 9002

rm jammy-server-cloudimg-amd64.img
```

### Step 2.6: Update Terraform

Update `terraform.tfvars` to move k3s-cp-03 to pve3 and add k3s-worker-03:

```hcl
control_planes = {
  "k3s-cp-01" = { ip = "192.168.10.21", node_name = "pve1", template_id = 9000 }
  "k3s-cp-02" = { ip = "192.168.10.22", node_name = "pve2", template_id = 9001 }
  "k3s-cp-03" = { ip = "192.168.10.23", node_name = "pve3", template_id = 9002 }
}

workers = {
  "k3s-worker-01" = { ip = "192.168.10.52", node_name = "pve1", template_id = 9000 }
  "k3s-worker-02" = { ip = "192.168.10.53", node_name = "pve2", template_id = 9001 }
  "k3s-worker-03" = { ip = "192.168.10.54", node_name = "pve3", template_id = 9002 }
}
```

**Important**: k3s-cp-03 changing `node_name` from pve2 to pve3 will trigger a
destroy+recreate in Terraform. Plan carefully:

1. First, drain and remove the old k3s-cp-03 from the k3s cluster
2. Then `terraform apply` to create the new VM on pve3
3. Then run Ansible to join it back to k3s

Update Ansible inventory (`ansible/inventory/hosts.yaml`) to add k3s-worker-03:

```yaml
k3s_workers:
  hosts:
    k3s-worker-01:
      ansible_host: 192.168.10.52
    k3s-worker-02:
      ansible_host: 192.168.10.53
    k3s-worker-03:
      ansible_host: 192.168.10.54
```

Also add pve3 to physical_hosts:

```yaml
physical_hosts:
  hosts:
    pve1:
      ansible_host: pve1.taild78f1d.ts.net
      ansible_user: root
    pve2:
      ansible_host: pve2.taild78f1d.ts.net
      ansible_user: root
    pve3:
      ansible_host: pve3.taild78f1d.ts.net
      ansible_user: root
```

### Step 2.7: Migrate k3s-cp-03 to pve3

Option A — Proxmox migration (preserves VM):
```bash
# From pve2
qm migrate <VMID-cp03> pve3 --targetstorage nvme-k3s --online 0
```

Option B — Terraform destroy+recreate (cleaner, but requires k3s rejoin):
```bash
cd terraform/proxmox

# Remove old cp-03 from k3s first
kubectl drain k3s-cp-03 --ignore-daemonsets --delete-emptydir-data
kubectl delete node k3s-cp-03

# Apply Terraform (will destroy old, create new on pve3)
terraform plan
terraform apply

# Run Ansible to configure and join k3s
ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/k3s/prepare.yaml --limit k3s-cp-03
ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/k3s/install.yaml --limit k3s-cp-03
```

### Step 2.8: Create k3s-worker-03

```bash
# Terraform creates the VM
terraform plan
terraform apply

# Ansible prepares and joins the worker
ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/k3s/prepare.yaml --limit k3s-worker-03
ansible-playbook -i ansible/inventory/hosts.yaml ansible/playbooks/k3s/install.yaml --limit k3s-worker-03
```

### Step 2.9: Verify cluster

```bash
kubectl get nodes -o wide
# Should show 6 nodes: 3 CP + 3 workers, all Ready

kubectl get pods -A | grep -v Running
# Check for any broken pods

kubectl -n longhorn-system get volumes
# Longhorn should start replicating to the new worker
```

---

## Phase 3: Swap RAM (pve2 ↔ pve3)

This requires both machines to be powered off simultaneously. Plan for a short
full-cluster outage.

### Step 3.1: Drain and shut down gracefully

```bash
# Drain workers on pve2 and pve3 (if k3s is already running on pve3)
kubectl drain k3s-worker-02 --ignore-daemonsets --delete-emptydir-data
kubectl drain k3s-worker-03 --ignore-daemonsets --delete-emptydir-data

# Shut down VMs on both hosts (Proxmox GUI or CLI)
# On pve2:
qm shutdown <each-VMID>
# On pve3:
qm shutdown <each-VMID>
```

### Step 3.2: Physical RAM swap

1. Power off pve2 and pve3
2. Remove 64 GB from pve2, install in pve3
3. Remove 32 GB from pve3 (or whatever it shipped with), install in pve2
4. Power on both

### Step 3.3: Verify and start VMs

```bash
# On both hosts, verify RAM
free -h

# Start all VMs
qm start <VMID>

# Uncordon workers
kubectl uncordon k3s-worker-02
kubectl uncordon k3s-worker-03
```

---

## Phase 4: Jellyfin LXC on pve3

### Step 4.1: Create media directory

```bash
# On pve3
mkdir -p /mnt/nvme-k3s/media/{movies,tv,music}
```

Note: with lvmthin you cannot simply mkdir on it — the thin pool is block storage,
not a filesystem. Instead, create a dedicated LVM volume for media:

```bash
# Create a regular (non-thin) LV for media storage
lvcreate -L 1T -n media nvme-k3s
mkfs.ext4 /dev/nvme-k3s/media
mkdir -p /mnt/media
echo '/dev/nvme-k3s/media /mnt/media ext4 defaults 0 2' >> /etc/fstab
mount /mnt/media
mkdir -p /mnt/media/{movies,tv,music}
```

### Step 4.2: Create Jellyfin LXC

```bash
# Download LXC template (Proxmox GUI: local → CT Templates → Templates)
# Or CLI:
pveam update
pveam download local debian-12-standard_12.7-1_amd64.tar.zst

# Create LXC on local-lvm (256 GB boot disk — small LXC, not on the data pool)
pct create 200 local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst \
  --hostname jellyfin \
  --memory 8192 \
  --cores 4 \
  --rootfs local-lvm:50 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.10.41/24,gw=192.168.10.1 \
  --unprivileged 0 \
  --features nesting=1 \
  --mp0 /mnt/media,mp=/media \
  --start 1
```

Key settings:
- `--unprivileged 0` — privileged LXC needed for `/dev/dri` GPU passthrough
- `--mp0` — bind-mounts `/mnt/media` from pve3 into the LXC at `/media`

### Step 4.3: GPU passthrough for Intel Quick Sync

```bash
# On pve3 host — add /dev/dri to the LXC config
echo 'lxc.cgroup2.devices.allow: c 226:* rwm' >> /etc/pve/lxc/200.conf
echo 'lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir' >> /etc/pve/lxc/200.conf

# Restart LXC
pct restart 200
```

### Step 4.4: Install Jellyfin inside the LXC

```bash
pct enter 200

apt update && apt install -y curl gnupg
curl -fsSL https://repo.jellyfin.org/install-debuntu.sh | bash

# Verify GPU access
ls -la /dev/dri/
# Should show renderD128

# Enable hardware transcoding in Jellyfin web UI:
# Dashboard → Playback → Hardware acceleration → Intel QSV (or VAAPI)
```

---

## Phase 5: Move Garage to 3145

Garage currently runs as a StatefulSet in k3s on k3s-worker-02.

### Step 5.1: Note current Garage config

```bash
# Get current Garage config from k3s
kubectl -n garage get configmap garage-config -o yaml
kubectl -n garage get secret garage-secrets -o yaml  # or check sops file
```

### Step 5.2: Install Garage on 3145 via Docker

```bash
# On 3145
ssh -p 22456 thomas@3145.taild78f1d.ts.net

mkdir -p /mnt/garage/{data,meta}

# Docker compose — use ARM64 image
cat > /opt/garage/docker-compose.yaml << 'COMPOSE'
services:
  garage:
    image: dxflrs/garage:v1.0
    container_name: garage
    restart: unless-stopped
    ports:
      - "3900:3900"   # S3 API
      - "3902:3902"   # Admin API
    volumes:
      - /mnt/garage/data:/data
      - /mnt/garage/meta:/meta
      - ./garage.toml:/etc/garage.toml
COMPOSE
```

Configure `garage.toml` based on the k3s configmap values. Update the S3 endpoint
in Velero to point to 3145's IP (use Tailscale IP `100.110.160.88:3900` from
cluster pods, or VLAN IP `192.168.20.10:3900` if reachable).

### Step 5.3: Migrate data

Export buckets from the old Garage instance and import into the new one, or use
`rclone sync` between old and new S3 endpoints.

### Step 5.4: Update Velero S3 endpoint

Update the Velero BackupStorageLocation to point to the new Garage on 3145.

### Step 5.5: Remove Garage from k3s

Once verified, remove the Garage StatefulSet, PV, and ArgoCD Application from
the cluster.

---

## Phase 6: Terraform and Ansible updates (summary)

### terraform.tfvars — final state

```hcl
proxmox_api_url = "https://192.168.10.20:8006/api2/json"
# Consider: should Terraform talk to pve3 instead? Or use a cluster-wide endpoint?

control_planes = {
  "k3s-cp-01" = { ip = "192.168.10.21", node_name = "pve1", template_id = 9000 }
  "k3s-cp-02" = { ip = "192.168.10.22", node_name = "pve2", template_id = 9001 }
  "k3s-cp-03" = { ip = "192.168.10.23", node_name = "pve3", template_id = 9002 }
}

cp_cores  = 2
cp_memory = 6144
cp_disk   = 50

workers = {
  "k3s-worker-01" = { ip = "192.168.10.52", node_name = "pve1", template_id = 9000 }
  "k3s-worker-02" = { ip = "192.168.10.53", node_name = "pve2", template_id = 9001 }
  "k3s-worker-03" = { ip = "192.168.10.54", node_name = "pve3", template_id = 9002 }
}

worker_cores  = 2
worker_memory = 6144
worker_disk   = 50

service_vms = {
  "gitlab-runner" = { ip = "192.168.10.31", node_name = "pve2", template_id = 9001, cores = 2, memory = 6144, disk = 40 }
}
```

Note: You may want to give pve3's worker more resources (4 cores, 16 GB RAM)
since pve3 has 64 GB. This would require making worker resources per-node instead
of global — consider using the `service_vms` pattern with per-VM specs, or create
a separate variable for pve3 workers.

### ansible/inventory/hosts.yaml — additions

- Add `k3s-worker-03` to `k3s_workers`
- Add `pve3` to `physical_hosts`

---

## Checklist — Full Migration Order

### Can do now (pve3 not ready yet)
- [ ] Phase 1: Restructure pve1 (256 GB boot + 1 TB data)

### When pve3 hardware is ready
- [ ] Phase 2: Install and configure pve3
- [ ] Phase 3: Swap RAM (pve2 ↔ pve3)
- [ ] Phase 2.6-2.9: Update Terraform/Ansible + migrate k3s-cp-03 + create worker-03
- [ ] Phase 4: Jellyfin LXC on pve3
- [ ] Phase 5: Move Garage to 3145

### Final verification
- [ ] 6 k3s nodes (3 CP + 3 workers), all Ready
- [ ] Longhorn healthy with replicas spread across 3 workers
- [ ] Velero backups working with Garage on 3145
- [ ] Jellyfin running with hardware transcoding
- [ ] PBS backing up all VMs
- [ ] ArgoCD all apps synced
- [ ] Tailscale on all new nodes
- [ ] SSH hardening applied to pve3
