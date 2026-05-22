resource "random_password" "dev" {
  length  = 24
  special = false
}

resource "wireguard_asymmetric_key" "router" {}

locals {
  router_ipv4_host   = "10.53.0.2"
  router_ipv4_cidr   = "24"

  router_network_config = templatefile("${path.module}/templates/router/network-config.yaml.tftpl", {
    ipv4_address = "${local.router_ipv4_host}/${local.router_ipv4_cidr}"
    gateway      = "10.53.0.1"
    nameservers  = ["1.1.1.1", "9.9.9.9"]
  })

  router_wg0_conf = templatefile("${path.module}/templates/router/wg0.conf.tftpl", {
    private_key = wireguard_asymmetric_key.router.private_key
  })

  router_nftables_conf = templatefile("${path.module}/templates/router/nftables.conf.tftpl", {
    lan_interface = "enX0"
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
  template = templatefile("${path.module}/templates/router/cloud-config.yaml.tftpl", {
    hostname              = "router"
    admin_username        = local.admin_username
    admin_password        = random_password.dev.result
    users                 = local.users
  })
}

resource "xenorchestra_vm" "router" {
  name_label       = "router"
  name_description = "WireGuard ingress + Pi-hole"

  cpus       = 1
  memory_max = 512 * 1024 * 1024 # 512 MiB

  template      = data.xenorchestra_template.ubuntu_2404_golden.id
  affinity_host = data.xenorchestra_host.shiitake.id
  clone_type    = "full"

  cloud_config = xenorchestra_cloud_config.router.template
  cloud_network_config = local.router_network_config
  
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
    expected_ip_cidr = "${local.router_ipv4_host}/${local.router_ipv4_cidr}"
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

resource "null_resource" "router_ingress_config" {
  depends_on = [xenorchestra_vm.router]

  triggers = {
    wg0_conf       = sha256(local.router_wg0_conf)
    nftables_conf  = sha256(local.router_nftables_conf)
    vm_id          = xenorchestra_vm.router.id
  }

  connection {
    type        = "ssh"
    host        = local.router_ipv4_host
    user        = local.admin_username
    password    = random_password.dev.result
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "for i in $(seq 1 60); do cloud-init status --wait && break || sleep 5; done",
      "mkdir -p /tmp/opentofu",
    ]
  }

  provisioner "file" {
    content     = local.router_nftables_conf
    destination = "/tmp/opentofu/nftables.conf"
  }

  provisioner "file" {
    content     = local.router_wg0_conf
    destination = "/tmp/opentofu/wg0.conf"
  }

  provisioner "remote-exec" {
    inline = [
      "set -eu",
      "sudo install -m 644 -o root -g root /tmp/opentofu/nftables.conf /etc/nftables.conf",
      "sudo install -m 600 -o root -g root /tmp/opentofu/wg0.conf /etc/wireguard/wg0.conf",
      "sudo systemctl enable nftables",
      "sudo systemctl restart nftables",
      "sudo systemctl enable wg-quick@wg0",
      "sudo systemctl restart wg-quick@wg0",
      "rm -rf /tmp/opentofu",
    ]
  }
}
