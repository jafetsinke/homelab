#!/bin/bash
# Managed by OpenTofu (rendered in cloud-init)
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

METADATA_DIR="/etc/opentofu/persistent-disks"
PRIMARY_MOUNT_FILE="${METADATA_DIR}/primary-mount"

resolve_data_mount() {
  local mount_path

  if [[ ! -r "${PRIMARY_MOUNT_FILE}" ]]; then
    echo "No persistent disk metadata found at ${PRIMARY_MOUNT_FILE} (run setup-data-disk first)" >&2
    return 1
  fi

  mount_path="$(head -n 1 "${PRIMARY_MOUNT_FILE}")"
  if [[ -z "${mount_path}" ]]; then
    echo "Persistent disk metadata is empty: ${PRIMARY_MOUNT_FILE}" >&2
    return 1
  fi

  if ! mountpoint -q "${mount_path}"; then
    echo "Persistent disk mount is not active: ${mount_path}" >&2
    return 1
  fi

  printf '%s\n' "${mount_path}"
}

ensure_bind_mount_entry() {
  local source_dir="$1" fstab_tmp

  fstab_tmp=$(mktemp)
  awk '$2 != "/etc/pihole" { print }' /etc/fstab > "${fstab_tmp}"
  printf '%s /etc/pihole none bind,nofail 0 0\n' "${source_dir}" >> "${fstab_tmp}"
  cat "${fstab_tmp}" > /etc/fstab
  rm -f "${fstab_tmp}"
}

DATA_MNT="$(resolve_data_mount)"
PIHOLE_DATA_DIR="${DATA_MNT}/pihole"

mkdir -p "${PIHOLE_DATA_DIR}" /etc/pihole
ensure_bind_mount_entry "${PIHOLE_DATA_DIR}"

if mountpoint -q /etc/pihole; then
  if [[ "$(stat -c '%d:%i' "${PIHOLE_DATA_DIR}")" != "$(stat -c '%d:%i' /etc/pihole)" ]]; then
    umount /etc/pihole
  fi
fi

mountpoint -q /etc/pihole || mount --bind "${PIHOLE_DATA_DIR}" /etc/pihole

if [[ -f /etc/pihole/pihole.toml ]] && [[ -s /etc/pihole/pihole.toml ]]; then
  echo "Reinstalling Pi-hole; config will be loaded from ${PIHOLE_DATA_DIR}"
else
  echo "First Pi-hole install; config will be stored on ${PIHOLE_DATA_DIR}"
  mkdir -p /etc/pihole
  touch /etc/pihole/pihole.toml
fi

curl -fsSL https://install.pi-hole.net -o /tmp/pihole-install.sh
PIHOLE_SKIP_OS_CHECK=true bash /tmp/pihole-install.sh --unattended
rm -f /tmp/pihole-install.sh

# The router is firewalled to LAN + WireGuard peers, so Pi-hole must answer
# DNS queries that arrive from those non-loopback interfaces.
pihole-FTL --config dns.listeningMode 'ALL'
pihole-FTL --config dns.specialDomains.iCloudPrivateRelay true

systemctl enable pihole-FTL
systemctl restart pihole-FTL
