locals {
  script_path            = abspath("${path.module}/../../scripts/xo-persistent-disk.py")
  setup_data_disk_script = file("${path.module}/../../scripts/setup-data-disk.sh")

  memory_max_bytes = var.resources.memory_max_mb * 1024 * 1024
  root_disk_bytes  = var.resources.root_disk_gb * 1024 * 1024 * 1024
  root_disk_label  = "${var.hostname}-root"

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
      {
        for key, value in {
          plain_text_passwd   = try(user.password, null)
          groups              = try(user.sudo, false) ? ["sudo"] : null
          sudo                = try(user.sudo, false) ? "ALL=(ALL) NOPASSWD:ALL" : null
          ssh_authorized_keys = length(try(user.ssh_keys, [])) > 0 ? user.ssh_keys : null
        } : key => value if value != null
      },
    )
  ]
  has_persistent_disks  = length(var.persistent_disks) > 0
  module_cloud_packages = local.has_persistent_disks ? ["parted"] : []
  module_cloud_write_files = local.has_persistent_disks ? [
    {
      path        = "/usr/local/sbin/setup-data-disk-opentofu"
      permissions = "0755"
      content     = local.setup_data_disk_script
    }
  ] : []
  module_cloud_runcmd = local.has_persistent_disks ? [
    "/usr/local/sbin/setup-data-disk-opentofu"
  ] : []

  cloud_config_overrides = merge(
    { hostname = var.hostname },
    length(local.cloud_config_users) > 0 ? { users = local.cloud_config_users } : {},
    length(distinct(concat(local.module_cloud_packages, var.cloud_config.packages))) > 0 ? {
      packages = distinct(concat(local.module_cloud_packages, var.cloud_config.packages))
    } : {},
    length(concat(local.module_cloud_write_files, var.cloud_config.write_files)) > 0 ? {
      write_files = concat(local.module_cloud_write_files, var.cloud_config.write_files)
    } : {},
    length(concat(local.module_cloud_runcmd, var.cloud_config.runcmd)) > 0 ? {
      runcmd = concat(local.module_cloud_runcmd, var.cloud_config.runcmd)
    } : {},
    local.cloud_config_swap != null ? { swap = local.cloud_config_swap } : {},
  )

  # NoCloud user-data must keep the cloud-config header; yamldecode/yamlencode strips comments.
  cloud_config_yaml = "#cloud-config\n${yamlencode(merge(local.cloud_config_default, local.cloud_config_overrides))}"

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
      name_label = coalesce(try(disk.name_label, null), "${var.hostname}-persistent-${disk.name}")
      sr_id      = coalesce(disk.sr_id, var.sr_id)
      size_bytes = floor(disk.size_gb * 1024 * 1024 * 1024)
      position   = try(disk.position, null) != null ? disk.position : ""
    }
  }
}

resource "xenorchestra_cloud_config" "this" {
  name     = "${var.hostname}-cloud-config"
  template = local.cloud_config_yaml
}

resource "terraform_data" "cloud_config_revision" {
  input = sha256(local.cloud_config_yaml)
}

resource "terraform_data" "network_config_revision" {
  input = sha256(coalesce(local.network_config, ""))
}

resource "xenorchestra_vm" "this" {
  template         = var.template_id
  name_label       = var.hostname
  name_description = var.name_description

  cpus       = var.resources.cpus
  memory_max = local.memory_max_bytes

  cloud_config         = xenorchestra_cloud_config.this.template
  cloud_network_config = local.network_config

  # The VM is created halted so persistent disks can be attached before first boot.
  destroy_cloud_config_vdi_after_boot = false

  power_state  = "Halted"
  auto_poweron = var.auto_poweron

  clone_type        = var.clone_type
  hvm_boot_firmware = var.hvm_boot_firmware
  tags              = var.tags

  network {
    network_id = var.network_id
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
    # Persistent data disks are attached outside xenorchestra_vm and must not be
    # reconciled away during refresh/apply.
    ignore_changes = [power_state, disk]
    replace_triggered_by = [
      terraform_data.cloud_config_revision,
      terraform_data.network_config_revision,
    ]
  }
}

data "external" "persistent_vdi_probe" {
  for_each = local.persistent_disks

  program = ["python3", local.script_path, "lookup-external"]

  query = {
    vm_id       = xenorchestra_vm.this.id
    vdi_name    = each.value.name_label
    sr_id       = each.value.sr_id
    xo_url      = coalesce(try(var.xo_auth.url, null), "")
    xo_token    = coalesce(try(var.xo_auth.token, null), "")
    xo_insecure = tostring(try(var.xo_auth.insecure, false))
  }

  depends_on = [xenorchestra_vm.this]
}

resource "null_resource" "persistent_disk" {
  for_each = local.persistent_disks

  triggers = {
    script_path    = local.script_path
    vm_id          = xenorchestra_vm.this.id
    name_label     = each.value.name_label
    sr_id          = each.value.sr_id
    size_bytes     = tostring(each.value.size_bytes)
    position       = each.value.position
    probe_exists   = data.external.persistent_vdi_probe[each.key].result["exists"]
    probe_attached = data.external.persistent_vdi_probe[each.key].result["attached_to_vm"]
    xo_url         = coalesce(try(var.xo_auth.url, null), "")
    xo_token       = coalesce(try(var.xo_auth.token, null), "")
    xo_insecure    = tostring(try(var.xo_auth.insecure, false))
  }

  depends_on = [xenorchestra_vm.this]

  provisioner "local-exec" {
    environment = {
      XO_URL      = lookup(self.triggers, "xo_url", "")
      XO_TOKEN    = lookup(self.triggers, "xo_token", "")
      XO_USERNAME = lookup(self.triggers, "xo_username", "")
      XO_PASSWORD = lookup(self.triggers, "xo_password", "")
      XO_INSECURE = lookup(self.triggers, "xo_insecure", "false")
    }
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
    environment = {
      XO_URL      = lookup(self.triggers, "xo_url", "")
      XO_TOKEN    = lookup(self.triggers, "xo_token", "")
      XO_USERNAME = lookup(self.triggers, "xo_username", "")
      XO_PASSWORD = lookup(self.triggers, "xo_password", "")
      XO_INSECURE = lookup(self.triggers, "xo_insecure", "false")
    }
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
    # Ensure VM start is re-attempted if persistent disks were reconciled.
    # The disk reconcile script may halt the VM, and depends_on alone does not
    # force this resource to be replaced.
    persistent_disks_revision = sha256(jsonencode({
      for key, disk in null_resource.persistent_disk : key => disk.id
    }))
    xo_url      = coalesce(try(var.xo_auth.url, null), "")
    xo_token    = coalesce(try(var.xo_auth.token, null), "")
    xo_insecure = tostring(try(var.xo_auth.insecure, false))
  }

  depends_on = [null_resource.persistent_disk]

  provisioner "local-exec" {
    environment = {
      XO_URL      = self.triggers.xo_url
      XO_TOKEN    = self.triggers.xo_token
      XO_INSECURE = self.triggers.xo_insecure
    }
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
    vm_id       = xenorchestra_vm.this.id
    vdi_name    = each.value.name_label
    sr_id       = each.value.sr_id
    xo_url      = coalesce(try(var.xo_auth.url, null), "")
    xo_token    = coalesce(try(var.xo_auth.token, null), "")
    xo_insecure = tostring(try(var.xo_auth.insecure, false))
  }

  depends_on = [
    null_resource.persistent_disk,
    null_resource.vm_start,
  ]
}
