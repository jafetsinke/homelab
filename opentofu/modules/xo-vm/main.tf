locals {
  script_path = abspath("${path.module}/../../scripts/xo-persistent-disk.py")

  memory_max_bytes = var.resources.memory_max_mb * 1024 * 1024
  root_disk_bytes  = var.resources.root_disk_gb * 1024 * 1024 * 1024
  root_disk_label  = "${var.name_label}-root"

  cloud_config_swap = try(var.resources.swap_size_mb, null) == null ? null : {
    filename = "/swap"
    size     = "${var.resources.swap_size_mb}M"
    maxsize  = "${var.resources.swap_size_mb}M"
  }

  cloud_config_default = yamldecode(file("${path.module}/cloud-config.default.yaml"))
  cloud_config_users = [
    for user in var.cloud_config.users : merge(
      {
        name        = user.name
        lock_passwd = try(user.password, null) == null
      },
      try(user.password, null) != null ? {
        plain_text_passwd = user.password
      } : {},
      try(user.sudo, false) ? {
        groups = ["sudo"]
        sudo   = "ALL=(ALL) NOPASSWD:ALL"
      } : {},
      length(try(user.ssh_keys, [])) > 0 ? {
        ssh_authorized_keys = user.ssh_keys
      } : {},
    )
  ]

  cloud_config_overrides = merge(
    length(local.cloud_config_users) > 0 ? { users = local.cloud_config_users } : {},
    length(var.cloud_config.packages) > 0 ? { packages = var.cloud_config.packages } : {},
    length(var.cloud_config.write_files) > 0 ? { write_files = var.cloud_config.write_files } : {},
    length(var.cloud_config.runcmd) > 0 ? { runcmd = var.cloud_config.runcmd } : {},
    local.cloud_config_swap != null ? { swap = local.cloud_config_swap } : {},
  )

  cloud_config_yaml = yamlencode(merge(local.cloud_config_default, local.cloud_config_overrides))

  network_config = var.network == null || try(var.network.ipv4_address, null) == null ? null : yamlencode({
    version = 2
    ethernets = {
      enX0 = merge(
        {
          match = {
            name = "enX0"
          }
          addresses = [var.network.ipv4_address]
        },
        try(var.network.gateway, null) != null ? {
          routes = [
            {
              to  = "default"
              via = var.network.gateway
            }
          ]
        } : {},
        length(try(var.network.nameservers, [])) > 0 ? {
          nameservers = {
            addresses = var.network.nameservers
          }
        } : {},
      )
    }
  })

  persistent_disks = {
    for disk in var.persistent_disks : disk.name => {
      name_label = coalesce(try(disk.name_label, null), "${var.name_label}-persistent-${disk.name}")
      sr_id      = coalesce(disk.sr_id, var.sr_id)
      size_bytes = floor(disk.size_gb * 1024 * 1024 * 1024)
      position   = coalesce(try(disk.position, null), "")
    }
  }
}

resource "xenorchestra_cloud_config" "this" {
  name     = "${var.name_label}-cloud-config"
  template = local.cloud_config_yaml
}

resource "xenorchestra_vm" "this" {
  template         = var.template_id
  name_label       = var.name_label
  name_description = var.name_description

  cpus       = var.resources.cpus
  memory_max = local.memory_max_bytes

  cloud_config         = xenorchestra_cloud_config.this.template
  cloud_network_config = local.network_config

  destroy_cloud_config_vdi_after_boot = true

  power_state  = "Halted"
  auto_poweron = var.auto_poweron

  clone_type        = var.clone_type
  hvm_boot_firmware = var.hvm_boot_firmware
  tags              = var.tags

  network {
    network_id       = var.network_id
    expected_ip_cidr = try(var.network.ipv4_address, null)
  }

  disk {
    sr_id      = var.sr_id
    name_label = local.root_disk_label
    size       = local.root_disk_bytes
  }

  timeouts {
    create = var.timeouts_create
  }

  lifecycle {
    ignore_changes = [power_state]
  }
}

resource "null_resource" "persistent_disk" {
  for_each = local.persistent_disks

  triggers = {
    script_path = local.script_path
    vm_id       = xenorchestra_vm.this.id
    name_label  = each.value.name_label
    sr_id       = each.value.sr_id
    size_bytes  = tostring(each.value.size_bytes)
    position    = each.value.position
  }

  depends_on = [xenorchestra_vm.this]

  provisioner "local-exec" {
    command = join(" ", concat(
      [
        "python3",
        self.triggers.script_path,
        "ensure",
        "--vm-id", self.triggers.vm_id,
        "--vdi-name", self.triggers.name_label,
        "--sr-id", self.triggers.sr_id,
        "--size-bytes", self.triggers.size_bytes,
      ],
      self.triggers.position != "" ? ["--position", self.triggers.position] : [],
    ))
  }

  provisioner "local-exec" {
    when = destroy
    command = join(" ", [
      "python3",
      self.triggers.script_path,
      "detach",
      "--vm-id", self.triggers.vm_id,
      "--vdi-name", self.triggers.name_label,
      "--sr-id", self.triggers.sr_id,
    ])
  }
}

resource "null_resource" "vm_start" {
  triggers = {
    script_path = local.script_path
    vm_id       = xenorchestra_vm.this.id
  }

  depends_on = [null_resource.persistent_disk]

  provisioner "local-exec" {
    command = join(" ", [
      "python3",
      self.triggers.script_path,
      "start-vm",
      "--vm-id", self.triggers.vm_id,
    ])
  }
}

data "external" "persistent_vdi" {
  for_each = local.persistent_disks

  program = ["python3", local.script_path, "lookup-external"]

  query = {
    vdi_name   = each.value.name_label
    sr_id      = each.value.sr_id
    size_bytes = tostring(each.value.size_bytes)
  }

  depends_on = [
    null_resource.persistent_disk,
    null_resource.vm_start,
  ]
}
