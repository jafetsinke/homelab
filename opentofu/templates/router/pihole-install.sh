#!/bin/bash
# Managed by OpenTofu (rendered in cloud-init)
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

DATA_MNT="$(find /mnt -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)"
if [[ -z "${DATA_MNT}" ]]; then
  echo "No VDI mount under /mnt (run setup-data-disk first)" >&2
  exit 1
fi

mkdir -p "${DATA_MNT}/pihole" /etc/pihole
if ! grep -q '/etc/pihole' /etc/fstab; then
  echo "${DATA_MNT}/pihole /etc/pihole none bind,nofail 0 0" >> /etc/fstab
fi
mountpoint -q /etc/pihole || mount --bind "${DATA_MNT}/pihole" /etc/pihole

if [[ -f /etc/pihole/pihole.toml ]] && [[ -s /etc/pihole/pihole.toml ]]; then
  echo "Reinstalling Pi-hole; config will be loaded from ${DATA_MNT}/pihole"
else
  echo "First Pi-hole install; config will be stored on ${DATA_MNT}/pihole"
  mkdir -p /etc/pihole
  touch /etc/pihole/pihole.toml
fi

curl -fsSL https://install.pi-hole.net -o /tmp/pihole-install.sh
PIHOLE_SKIP_OS_CHECK=true bash /tmp/pihole-install.sh --unattended
rm -f /tmp/pihole-install.sh

systemctl enable pihole-FTL
systemctl restart pihole-FTL
