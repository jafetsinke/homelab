#!/usr/bin/env bash
# Prepare an installed Ubuntu VM for use as an XCP-ng / Xen Orchestra template.
# Clones must read cloud-init from the XO config drive (xvdb, NoCloud label "cidata").
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

sudo apt-get update -qq
sudo apt-get install -y -qq cloud-init cloud-initramfs-growroot

sudo rm -f /etc/cloud/cloud-init.disabled

sudo rm -f /etc/cloud/cloud.cfg.d/90-installer-network.cfg
sudo rm -f /etc/cloud/cloud.cfg.d/99-installer.cfg
sudo rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg
sudo rm -f /etc/netplan/50-cloud-init.yaml
sudo rm -f /etc/netplan/00-installer-config.yaml

# Xen Orchestra attaches a small config drive (xvdb / cidata). NoCloud must be enabled.
sudo tee /etc/cloud/cloud.cfg.d/90-xcp-datasources.cfg >/dev/null <<'EOF'
datasource_list: [ NoCloud, ConfigDrive, None ]
datasource:
  NoCloud:
    fs_label: cidata
  ConfigDrive:
    dsmode: local
EOF

if [[ -f /etc/cloud/clean.d/99-installer ]]; then
  sudo chmod a-x /etc/cloud/clean.d/99-installer
fi

sudo truncate -s 0 /etc/machine-id
if [[ -e /var/lib/dbus/machine-id ]]; then
  sudo rm -f /var/lib/dbus/machine-id
  sudo ln -s /etc/machine-id /var/lib/dbus/machine-id
fi

sudo find /etc/ssh -type f -name 'ssh_host_*' -delete

sudo systemctl enable xe-linux-distribution.service 2>/dev/null || true
sudo systemctl enable cloud-init-local.service cloud-init.service cloud-config.service cloud-final.service 2>/dev/null || true

# Drop all Packer/installer cloud-init state so clones run init again (not reuse old logs).
sudo cloud-init clean --logs --seed --force 2>/dev/null || sudo cloud-init clean --logs --seed
sudo rm -rf /var/lib/cloud/instances /var/lib/cloud/instance /var/lib/cloud/data /var/lib/cloud/sem
sudo rm -rf /var/lib/cloud/seed /var/lib/cloud/scripts /var/lib/cloud/handlers
sudo rm -rf /var/log/cloud-init.log /var/log/cloud-init-output.log /var/log/cloud-init*
sudo rm -rf /run/cloud-init /run/cloud-init.tmp

if [[ -e /var/lib/cloud/data/status.json ]]; then
  echo "cloud-init state was not cleared under /var/lib/cloud" >&2
  exit 1
fi
if [[ -e /var/log/cloud-init.log ]]; then
  echo "cloud-init logs were not removed" >&2
  exit 1
fi

sudo apt-get clean
