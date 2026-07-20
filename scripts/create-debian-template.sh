#!/usr/bin/env bash
# Create a Debian 13 (trixie) cloud-init template on a Proxmox node.
#
# Run this ON the Proxmox node that will host the VMs cloned from it. For PBS
# that is pve2 (the services resource clones same-node), so:
#   scp scripts/create-debian-template.sh root@pve2:/tmp/ && ssh root@pve2 'bash /tmp/create-debian-template.sh'
#
# Produces VMID 9002 as a template. Terraform's service_vms.pbs then clones it.
# Idempotent-ish: refuses to clobber an existing VMID 9002.
set -euo pipefail

VMID="${VMID:-9002}"
STORAGE="${STORAGE:-vmdata}"          # same lvmthin pool Terraform uses (var.vm_datastore)
IMG_URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
IMG="/var/lib/vz/template/iso/$(basename "$IMG_URL")"

if qm status "$VMID" >/dev/null 2>&1; then
  echo "VMID $VMID already exists — aborting so we don't clobber it." >&2
  exit 1
fi

echo "==> Downloading Debian 13 genericcloud image"
mkdir -p "$(dirname "$IMG")"
[ -f "$IMG" ] || wget -O "$IMG" "$IMG_URL"

echo "==> Creating VM $VMID"
qm create "$VMID" \
  --name debian-13-cloudinit \
  --machine q35 \
  --bios ovmf \
  --efidisk0 "${STORAGE}:1,efitype=4m,pre-enrolled-keys=0" \
  --cpu host --cores 2 --memory 2048 \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-single \
  --serial0 socket --vga serial0 \
  --agent enabled=1

echo "==> Importing cloud image as the boot disk"
qm importdisk "$VMID" "$IMG" "$STORAGE"
qm set "$VMID" --virtio0 "${STORAGE}:vm-${VMID}-disk-1"
qm set "$VMID" --boot order=virtio0
qm set "$VMID" --ide2 "${STORAGE}:cloudinit"
# cloud-init defaults — Terraform overrides ip/user/keys per-VM on clone.
qm set "$VMID" --ciuser ubuntu --ipconfig0 ip=dhcp

echo "==> Converting to template"
qm template "$VMID"

echo "==> Done. Template $VMID (debian-13-cloudinit) ready on $(hostname)."
echo "    Next: cd terraform/proxmox && terraform plan  (creates the PBS VM)."
