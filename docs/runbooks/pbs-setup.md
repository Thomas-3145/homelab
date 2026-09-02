# Runbook — Proxmox Backup Server on pve1 (with R2 offsite)

Brings PBS back online as a VM on pve1 and wires it into the 3-2-1 backup plan:
PBS holds the **local** backup datastore; a Cloudflare R2 S3 endpoint is the
**offsite** copy. Path A (IaC): Terraform VM + Ansible config.

## Why pve1

A backup datastore is a years-long continuous write load, so the deciding factor
was SSD endurance rather than free space or CPU load (measured 2026-08-23):

| | pve1 vmdata | pve2 vmdata | pve3 vmdata |
|---|---|---|---|
| Disk | Samsung 970 EVO Plus 1TB | (n/a — busiest node) | Netac NVMe 1TB |
| Wear | 4 % after 36.9 TB | — | 1 % after 4.2 TB |
| Wear per TB written | **0.11 %/TB** | — | 0.24 %/TB |

Netac looks healthier only because it is new; normalised against data actually
written it wears roughly twice as fast. pve1 also has the healthiest boot disk
(0 % wear) and the lowest load, and it already hosts templates 9000/9001.
pve3 was rejected despite having the most RAM: PBS uses ext4, not ZFS, so it has
no ARC to feed — and pve3 already carries the NUT server role plus a 35 %-worn
boot disk. (The NUT half of that argument has since expired: the NUT server moved
to pve2 around 2026-08-31. The worn boot disk still stands, so the placement
decision is unchanged.)


## Status

Steps 1–3 completed 2026-08-23: VM 110 on pve1, PBS 4.2.5 running, datastore
`vm-backup` mounted on `/dev/vdb` (295 GB), prune/GC/verify jobs active, SSH
hardened to 22456, Tailscale up (`100.76.99.47`). **Remaining: steps 4–6.**

## Prerequisites

- pve1 live (3-node quorum) — ✅
- R2 credentials ready. **Rotate the R2 token first** (it was in cleartext once —
  see memory `todo-rotate-r2-token`) and do both in one go: bucket `homelab-backups`,
  region `auto`, endpoint `https://<accountid>.r2.cloudflarestorage.com`.

## 1. Debian 13 template on pve1

PBS needs Debian (not the Ubuntu 9000 template). Build VMID 9002 **on pve1** so the
Terraform clone is same-node:

```bash
scp scripts/create-debian-template.sh root@pve1:/tmp/
ssh root@pve1 'bash /tmp/create-debian-template.sh'   # creates template 9002
```

## 2. Provision the VM (Terraform)

`service_vms.pbs` is already defined in `terraform/proxmox/terraform.tfvars`
(pve1, 192.168.10.30, 2 vCPU / 4 GB / 20 GB boot + 300 GB datastore disk on virtio1).

```bash
cd terraform/proxmox
terraform plan     # review: 1 VM to add, no other changes
terraform apply
```

## 3. Configure PBS (Ansible)

```bash
cd ansible
ansible-playbook -i inventory/hosts.yaml playbooks/pbs.yaml --check --diff   # dry-run
ansible-playbook -i inventory/hosts.yaml playbooks/pbs.yaml
```

This runs `common` (SSH → 22456, fail2ban, Tailscale) then `pbs` (repo, install,
formats/mounts the 300 GB datastore disk at `/mnt/datastore/vm-backup`, creates the
datastore + prune/GC/verify jobs). **Verify on Debian:** the `common` role was written
for Ubuntu VMs — watch the `--check` output for any apt/package task that assumes
Ubuntu, and adjust if needed.

**Debian gotchas fixed on 2026-08-23** (all now handled in the repo, listed so a
re-run on another Debian guest makes sense):

1. **Cloud-init inherited the host's Tailscale resolver.** Every pve node's
   `/etc/resolv.conf` is owned by Tailscale (`100.100.100.100`), and without an
   explicit `dns` block Proxmox hands that to the guest — which cannot reach it
   until Tailscale is up, but Tailscale is installed by `common`, which needs DNS.
   Fixed by adding `initialization { dns { servers } }` to the `services` resource
   in `terraform/proxmox/main.tf`. **The k3s VM resources still lack this** — worth
   adding during the cluster rebuild.
2. **`gnupg` missing.** `apt_repository` shells out to `gpg`; Ubuntu cloud images
   ship it, the Debian genericcloud image does not. Added to the `common` package list.
3. **The sshd restart handler can be lost.** If the play fails after
   `Configure SSH port` reports *changed* (it did, on gotcha 2), handlers never run.
   The next run is idempotent, so the task reports *ok*, never notifies, and sshd
   keeps listening on 22 while `sshd -T` claims 22456. Check with
   `ss -lntp | grep 22456` after a failed-then-fixed run; recover with
   `systemctl restart ssh.service` or re-run with `--force-handlers`.

Also note `proxmox-backup-manager` lives in `/usr/sbin`, so it is not on the
`ubuntu` user's PATH — use `sudo`.

### qemu-guest-agent (added 2026-08-23)

Without it Proxmox cannot freeze the guest filesystem before a vzdump snapshot,
so backups are crash-consistent rather than filesystem-consistent. Now handled by
the `common` role (VMs only — skipped on the LXC guests) and by
`agent { enabled = true }` on every VM resource in `terraform/proxmox/main.tf`.

Apply it on its own without triggering the role's `upgrade: dist`:

```bash
ansible-playbook -i inventory/hosts.yaml playbooks/vm-setup.yaml \
  -e target='k3s_control_plane:k3s_workers' --tags qemu-agent
ansible-playbook -i inventory/hosts.yaml playbooks/pbs.yaml --tags qemu-agent
```

**The agent needs a power-cycle, and `terraform apply` does it for you — all at
once.** The virtio-serial device is only added at machine start, so flipping
`agent.enabled` makes the bpg provider stop and start the VM. The plan says
"updated in-place" and gives no hint of this. On 2026-08-23 that rebooted all six
k3s nodes nearly simultaneously; the cluster recovered (all nodes Ready, no pods
down) but etcd quorum was briefly at risk. **Roll it out one node at a time:**

```bash
terraform apply -target='proxmox_virtual_environment_vm.k3s_workers["k3s-worker-01"]'
# wait for Ready, then the next
```

Verify from the host: `qm agent <vmid> ping` and `qm agent <vmid> fsfreeze-status`
(expect `thawed`).

Set the PBS admin/web password (port 8007) once. `root@pam` authenticates through
system PAM, so this is the Linux root password — *not*
`proxmox-backup-manager user update --password`, which explicitly ignores the flag.
The Debian cloud image ships root locked (`passwd -S root` → `L`), so:

```bash
ssh -p 22456 ubuntu@192.168.10.30
sudo passwd root
```

## 4. Offsite: S3 endpoint → Cloudflare R2

PBS 4.x native S3 backend. **Installed version is 4.2.5**, and
`proxmox-backup-manager datastore create --help` exposes `--backend`, so native
S3-backed datastores are supported on this build. Then in the PBS UI
**Configuration → S3 Endpoints** (or CLI), add R2:

- Endpoint: `https://<accountid>.r2.cloudflarestorage.com`
- Region: `auto`, path-style addressing (R2 requirement)
- Bucket: `homelab-backups`, Access key / Secret: the rotated R2 token

Then either back the `vm-backup` datastore with the S3 endpoint, or add a **sync job**
that pushes `vm-backup` to R2 on a schedule. If native S3 is unstable on your version,
fall back to a local datastore + a scheduled `rclone sync` to R2.

## 5. Wire PVE → PBS

Storage config is cluster-wide (`/etc/pve/storage.cfg` is shared through pmxcfs),
so add this **once** at Datacenter → Storage → Add → Proxmox Backup Server — not
per node. Server `192.168.10.30`, datastore `vm-backup`.

Authenticate with the API token rather than the root password, so no password
ends up in `storage.cfg`: create `root@pam!pve` in PBS under Configuration →
Access Control → API Token, grant it role `DatastoreBackup` on path
`/datastore/vm-backup`, and store the secret in the password manager (nothing in
this repo reads it). The secret is shown only once. Fingerprint as of
2026-08-23 (re-read with `sudo proxmox-backup-manager cert info` if the cert is
regenerated):

```
84:0b:11:7e:95:38:46:e9:68:ee:98:92:75:92:e7:36:91:8a:18:c9:06:3a:f7:37:1c:81:a9:6e:09:2a:ae:14
```

Create a backup job (Datacenter → Backup) targeting the PBS storage.

Two traps hit on 2026-08-23:

- **The Storage dropdown defaults to `local`.** A job created without changing it
  writes VM images to `/var/lib/vz/dump` on each node — pve1 has ~55 GB free there,
  so six k3s VMs would fill it. Verify with `grep storage /etc/pve/jobs.cfg` after
  creating the job; the Storage column in the Backup list shows it too.
- **An old `pbs-daily` job from the RPi5 era was still present**, disabled but with
  `all 1` (every guest, including the PBS VM itself and arr-stack's 500 GB media).
  It was the source of the recurring `could not activate storage 'pbs'` task errors.
  Removed.

Storage is cluster-wide, but the *job* runs per node — expect one vzdump task on
each of pve1/pve2/pve3.

Scope decided
2026-08-23: **k3s VMs + service configs only** — the arr-stack media disk (532 GB of
already-compressed media) dedupes poorly and would blow past the 300 GB datastore.
App data is covered separately by Velero.

## 6. Verify (close the DR gap)

- A backup job completes and appears in the `vm-backup` datastore.
- The verify job passes.
- The R2 bucket receives objects (offsite copy exists).
- Do a **test restore** of one VM — that's the actual DR-test (`todo-dr-and-ups`).
