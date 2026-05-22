resource "random_password" "dev" {
  length  = 16
  special = false
}

locals {
  router_ipv4_cidr   = "10.53.0.2/24"
  router_gateway     = "10.53.0.1"
  router_nameservers = ["1.1.1.1", "9.9.9.9"]

  router_network_config = templatefile("${path.module}/templates/router-network-config.yaml.tftpl", {
    ipv4_cidr   = local.router_ipv4_cidr
    gateway     = local.router_gateway
    nameservers = local.router_nameservers
  })
}

# Tracks user-data + network-config; any change forces a new VM so cloud-init runs on first boot.
resource "terraform_data" "router_cloud_revision" {
  input = sha256(join("\n\n", [
    xenorchestra_cloud_config.router.template,
    local.router_network_config,
  ]))
}

resource "xenorchestra_cloud_config" "router" {
  name = "router-cloud-config"
  template = templatefile("${path.module}/templates/router-cloud-config.yaml.tftpl", {
    hostname       = "router"
    admin_username = local.admin_username
    admin_password = random_password.dev.result
    users          = local.users
  })
}

resource "xenorchestra_vm" "router" {
  name_label       = "router"
  name_description = "WireGuard Ingress + Pi-hole"

  cpus       = 1
  memory_max = 512 * 1024 * 1024 # 512 MiB

  template      = data.xenorchestra_template.ubuntu_2404_golden.id
  affinity_host = data.xenorchestra_host.shiitake.id
  clone_type    = "full"

  cloud_config                        = xenorchestra_cloud_config.router.template
  cloud_network_config                = local.router_network_config
  destroy_cloud_config_vdi_after_boot = true

  lifecycle {
    replace_triggered_by = [
      terraform_data.router_cloud_revision,
    ]
  }

  power_state  = "Running"
  auto_poweron = true

  hvm_boot_firmware = "uefi"

  network {
    network_id       = data.xenorchestra_pif.eth0.network
    expected_ip_cidr = local.router_ipv4_cidr
  }

  disk {
    sr_id      = data.xenorchestra_sr.default.id
    name_label = data.xenorchestra_template.ubuntu_2404_golden.name_label
    size       = 20 * 1024 * 1024 * 1024 # 20 GiB
  }

  timeouts {
    create = "5m"
  }

  tags = [
    "opentofu",
    "ubuntu-24.04",
  ]
}
