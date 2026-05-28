resource "random_password" "dev" {
  length  = 24
  special = false
}

resource "random_password" "pihole" {
  length  = 24
  special = false
}

resource "wireguard_asymmetric_key" "router" {}

locals {
  router_ipv4_host = "10.53.0.2"
  router_ipv4_cidr = "24"

  router_wg0_conf = templatefile("${path.module}/templates/router/wg0.conf.tftpl", {
    private_key = wireguard_asymmetric_key.router.private_key
  })

  router_nftables_conf = templatefile("${path.module}/templates/router/nftables.conf.tftpl", {
    lan_interface = "enX0"
  })

  router_pihole_install_script = file("${path.module}/templates/router/pihole-install.sh")
  router_finalize_script       = <<-EOF
  #!/bin/bash
  set -euo pipefail

  # Wait for Pi-hole to be installed and healthy.
  for i in $(seq 1 120); do
    if command -v pihole >/dev/null 2>&1 && pihole status >/dev/null 2>&1; then
      break
    fi
    sleep 10
  done
  command -v pihole >/dev/null 2>&1 || (echo 'Pi-hole not installed after cloud-init' >&2; exit 1)

  # Validate persistent disk + bind mount are present (required for persistence).
  DATA_MNT=$(sed -n '1p' /etc/opentofu/persistent-disks/primary-mount 2>/dev/null || true)
  [ -n "$DATA_MNT" ] && mountpoint -q "$DATA_MNT" || (echo 'No persistent data disk metadata or mounted data disk found' >&2; exit 1)
  [ -d "$DATA_MNT/pihole" ] || (echo 'Pi-hole data directory missing on persistent disk' >&2; exit 1)
  mountpoint -q /etc/pihole || (echo '/etc/pihole not bind-mounted' >&2; exit 1)
  findmnt -n -o SOURCE /etc/pihole | grep -F "[$DATA_MNT/pihole]" >/dev/null || (echo '/etc/pihole is not backed by the persistent data disk' >&2; exit 1)

  # Apply router configuration.
  pihole setpassword '${random_password.pihole.result}'
  systemctl enable nftables
  systemctl restart nftables
  systemctl enable wg-quick@wg0
  systemctl restart wg-quick@wg0
  systemctl restart pihole-FTL
  EOF
  router_cloud_config_users = concat(
    [
      {
        name     = local.admin_username
        password = random_password.dev.result
        sudo     = true
      }
    ],
    local.users,
  )
}

module "router" {
  source  = "./modules/xo-vm"
  xo_auth = local.xo_auth

  hostname        = "router"
  template_id     = data.xenorchestra_template.ubuntu_2404_golden.id
  network_id      = data.xenorchestra_pif.eth0.network
  sr_id           = data.xenorchestra_sr.default.id
  clone_type      = "full"
  auto_poweron    = true
  timeouts_create = "5m"

  resources = {
    cpus          = 1
    memory_max_mb = 512
    root_disk_gb  = 20
    swap_size_mb  = 512
  }

  cloud_config = {
    users = local.router_cloud_config_users
    packages = [
      "wireguard",
      "wireguard-tools",
      "nftables",
      "curl",
      "ca-certificates",
    ]
    write_files = [
      {
        path        = "/usr/local/sbin/pihole-install-opentofu"
        permissions = "0755"
        content     = local.router_pihole_install_script
      },
      {
        path        = "/usr/local/sbin/router-finalize-opentofu"
        permissions = "0755"
        content     = local.router_finalize_script
      },
      {
        path        = "/etc/nftables.conf"
        permissions = "0644"
        content     = local.router_nftables_conf
      },
      {
        path        = "/etc/wireguard/wg0.conf"
        permissions = "0600"
        content     = local.router_wg0_conf
      },
    ]
    runcmd = [
      "id -u packer >/dev/null 2>&1 && userdel -f -r packer || true",
      "id -u ubuntu >/dev/null 2>&1 && userdel -f -r ubuntu || true",
      "sysctl -w net.ipv4.ip_forward=1",
      "/usr/local/sbin/pihole-install-opentofu",
      "/usr/local/sbin/router-finalize-opentofu",
    ]
  }

  network = {
    ipv4_address = "${local.router_ipv4_host}/${local.router_ipv4_cidr}"
    gateway      = "10.53.0.1"
    nameservers  = ["1.1.1.1", "9.9.9.9"]
  }

  persistent_disks = [
    {
      name       = "data"
      size_gb    = 5
      name_label = "router-data"
    },
  ]

  name_description = "WireGuard ingress + Pi-hole"
  tags = [
    "opentofu",
    "ubuntu-24.04",
  ]
}
