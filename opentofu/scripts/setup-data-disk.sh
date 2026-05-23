#!/bin/bash
# Managed by OpenTofu — detect non-root block devices and mount at /mnt/<disk_id>
set -euo pipefail

root_disk_dev() {
  local src pk
  src=$(findmnt -n -o SOURCE -T /)
  pk=$(lsblk -ndo PKNAME "${src}" 2>/dev/null | head -1)
  if [[ -z "${pk}" ]]; then
    pk=$(basename "${src}")
  fi
  echo "/dev/${pk}"
}

disk_id_for() {
  local dev="$1" part="${dev}1" id xen_dev

  if command -v xe >/dev/null 2>&1; then
    xen_dev=$(basename "${dev}")
    id=$(xe vbd-list "device=${xen_dev}" params=vdi-uuid --minimal 2>/dev/null || true)
    if [[ -n "${id}" ]]; then
      echo "${id}"
      return
    fi
  fi

  if [[ -b "${part}" ]]; then
    id=$(blkid -s PARTUUID -o value "${part}" 2>/dev/null || true)
    if [[ -n "${id}" ]]; then
      echo "${id}"
      return
    fi
  fi

  id=$(udevadm info -q symlink -n "${dev}" 2>/dev/null \
    | tr ' ' '\n' \
    | sed -n 's|.*/||p' \
    | grep -vFx "$(basename "${dev}")" \
    | head -1 || true)
  if [[ -n "${id}" ]]; then
    echo "${id}"
    return
  fi

  basename "${dev}"
}

prepare_partition() {
  local dev="$1" part="${dev}1"

  if ! blkid "${part}" >/dev/null 2>&1; then
    parted -s "${dev}" mklabel gpt mkpart primary ext4 0% 100%
    partprobe "${dev}"
    udevadm settle
    mkfs.ext4 "${part}"
  fi

  echo "${part}"
}

mount_disk() {
  local dev="$1" disk_id part uuid mnt

  disk_id=$(disk_id_for "${dev}")
  disk_id=${disk_id//\//-}
  part=$(prepare_partition "${dev}")
  uuid=$(blkid -s UUID -o value "${part}")
  mnt="/mnt/${disk_id}"

  mkdir -p "${mnt}"
  if ! grep -q "${uuid}" /etc/fstab; then
    echo "UUID=${uuid} ${mnt} ext4 defaults,nofail 0 2" >> /etc/fstab
  fi
  mountpoint -q "${mnt}" || mount "${mnt}"
  echo "Mounted ${dev} at ${mnt}"
}

ROOT_DEV=$(root_disk_dev)
mounted=0

while IFS= read -r dev; do
  [[ -b "${dev}" ]] || continue
  [[ "${dev}" == "${ROOT_DEV}" ]] && continue
  [[ "$(lsblk -ndo RM "${dev}" 2>/dev/null)" == "1" ]] && continue
  if lsblk -rn -o MOUNTPOINT "${dev}" 2>/dev/null | grep -qx '/'; then
    continue
  fi

  mount_disk "${dev}"
  mounted=$((mounted + 1))
done < <(lsblk -rpnpo NAME,TYPE | awk '$2=="disk" { print $1 }')

if [[ "${mounted}" -eq 0 ]]; then
  echo "No additional block devices to mount" >&2
fi
