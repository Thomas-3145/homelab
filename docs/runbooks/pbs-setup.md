# Runbook — Proxmox Backup Server on pve2 (with R2 offsite)

Brings PBS back online as a VM on pve2 and wires it into the 3-2-1 backup plan:
PBS holds the **local** backup datastore; a Cloudflare R2 S3 endpoint is the
**offsite** copy. Path A (IaC): Terraform VM + Ansible config.

## Prerequisites

- pve2 live (3-node quorum) — ✅
- R2 credentials ready. **Rotate the R2 token first** (it was in cleartext once —
  see memory `todo-rotate-r2-token`) and do both in one go: bucket `homelab-backups`,
  region `auto`, endpoint `https://<accountid>.r2.cloudflarestorage.com`.

## 1. Debian 13 template on pve2

PBS needs Debian (not the Ubuntu 9000 template). Build VMID 9002 **on pve2** so the
Terraform clone is same-node:

```bash
scp scripts/create-debian-template.sh root@pve2:/tmp/
ssh root@pve2 'bash /tmp/create-debian-template.sh'   # creates template 9002
```

## 2. Provision the VM (Terraform)

`service_vms.pbs` is already defined in `terraform/proxmox/terraform.tfvars`
(pve2, 192.168.10.30, 2 vCPU / 4 GB / 20 GB boot + 300 GB datastore disk on virtio1).

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

Set the PBS admin/web password (port 8007) once:
```bash
ssh -p 22456 ubuntu@192.168.10.30 'sudo proxmox-backup-manager user update root@pam --password'
```

## 4. Offsite: S3 endpoint → Cloudflare R2

PBS 4.x native S3 backend. Confirm the installed version first
(`proxmox-backup-manager version`); S3-backed datastores need 4.x. Then in the PBS UI
**Configuration → S3 Endpoints** (or CLI), add R2:

- Endpoint: `https://<accountid>.r2.cloudflarestorage.com`
- Region: `auto`, path-style addressing (R2 requirement)
- Bucket: `homelab-backups`, Access key / Secret: the rotated R2 token

Then either back the `vm-backup` datastore with the S3 endpoint, or add a **sync job**
that pushes `vm-backup` to R2 on a schedule. If native S3 is unstable on your version,
fall back to a local datastore + a scheduled `rclone sync` to R2.

## 5. Wire PVE → PBS

On each pve node, add PBS as a storage target (Datacenter → Storage → Add → Proxmox
Backup Server), fingerprint from `proxmox-backup-manager cert info`. Create a backup
job (Datacenter → Backup) targeting the PBS storage.

## 6. Verify (close the DR gap)

- A backup job completes and appears in the `vm-backup` datastore.
- The verify job passes.
- The R2 bucket receives objects (offsite copy exists).
- Do a **test restore** of one VM — that's the actual DR-test (`todo-dr-and-ups`).
