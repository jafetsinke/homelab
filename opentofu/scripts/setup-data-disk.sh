#!/bin/bash
# Managed by OpenTofu — detect non-root, non-cloud-init block devices and mount at /mnt/<disk_id>
set -euo pipefail

# Record the actual mounted persistent-disk paths so later provisioning steps
# do not have to guess based on directory names under /mnt.
METADATA_DIR="/etc/opentofu/persistent-disks"
DISK_MAP_DIR="${METADATA_DIR}/by-id"
PRIMARY_MOUNT_FILE="${METADATA_DIR}/primary-mount"
MOUNTS_FILE="${METADATA_DIR}/mounts"
MOUNTS_TMP=$(mktemp)
trap 'rm -f "${MOUNTS_TMP}"' EXIT

root_disk_dev() {
  local src pk
  src=$(findmnt -n -o SOURCE -T /)
  pk=$(lsblk -ndo PKNAME "${src}" 2>/dev/null | head -1)
  if [[ -z "${pk}" ]]; then
    pk=$(basename "${src}")
  fi
  echo "/dev/${pk}"
}

blkid_value() {
  local field="$1" target="$2"
  blkid -s "${field}" -o value "${target}" 2>/dev/null || true
}

is_cloud_init_drive() {
  local dev="$1" target label type

  for target in "${dev}" "${dev}1"; do
    [[ -b "${target}" ]] || continue

    label=$(blkid_value LABEL "${target}")
    if [[ -z "${label}" ]]; then
      label=$(blkid_value LABEL_FATBOOT "${target}")
    fi
    type=$(blkid_value TYPE "${target}")

    if [[ "${label,,}" == "cidata" ]]; then
      echo "Skipping cloud-init drive ${dev} (${target}, type=${type:-unknown}, label=${label})" >&2
      return 0
    fi
  done

  return 1
}

reset_mount_metadata() {
  mkdir -p "${DISK_MAP_DIR}"
  rm -f "${PRIMARY_MOUNT_FILE}" "${MOUNTS_FILE}"
  rm -f "${DISK_MAP_DIR}"/* 2>/dev/null || true
  : > "${MOUNTS_TMP}"
}

record_mount_metadata() {
  local disk_id="$1" mnt="$2"

  printf '%s\n' "${mnt}" >> "${MOUNTS_TMP}"
  printf '%s\n' "${mnt}" > "${DISK_MAP_DIR}/${disk_id}"
  if [[ ! -s "${PRIMARY_MOUNT_FILE}" ]]; then
    printf '%s\n' "${mnt}" > "${PRIMARY_MOUNT_FILE}"
  fi
}

persist_mount_metadata() {
  [[ -s "${MOUNTS_TMP}" ]] || return 0
  awk '!seen[$0]++' "${MOUNTS_TMP}" > "${MOUNTS_FILE}"
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
  record_mount_metadata "${disk_id}" "${mnt}"
  echo "Mounted ${dev} at ${mnt}"
}

ROOT_DEV=$(root_disk_dev)
mounted=0
reset_mount_metadata

while IFS= read -r dev; do
  [[ -b "${dev}" ]] || continue
  [[ "${dev}" == "${ROOT_DEV}" ]] && continue
  [[ "$(lsblk -ndo RM "${dev}" 2>/dev/null)" == "1" ]] && continue
  is_cloud_init_drive "${dev}" && continue
  if lsblk -rn -o MOUNTPOINT "${dev}" 2>/dev/null | grep -qx '/'; then
    continue
  fi

  mount_disk "${dev}"
  mounted=$((mounted + 1))
done < <(lsblk -rpnpo NAME,TYPE | awk '$2=="disk" { print $1 }')

if [[ "${mounted}" -eq 0 ]]; then
  echo "No additional block devices to mount" >&2
else
  persist_mount_metadata
fi
