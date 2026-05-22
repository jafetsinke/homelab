packer {
  required_version = ">= 1.9.0"

  required_plugins {
    xenserver = {
      version = ">= 0.9.0"
      source  = "github.com/vatesfr/xenserver"
    }
  }
}

locals {
  ubuntu_version = "24.04.4"
  timestamp      = regex_replace(timestamp(), "[- TZ:]", "")

  # Stable name for OpenTofu (default). Use -force on build to remove an existing template
  # with the same name_label (see packer/Makefile). If you cannot use -force, set
  # append_build_timestamp = true so each build gets a unique name.
  template_name_label = var.append_build_timestamp ? "${var.vm_name}-${local.timestamp}" : var.vm_name

  # https://releases.ubuntu.com/24.04.4/SHA256SUMS
  ubuntu_iso_url      = "https://releases.ubuntu.com/${local.ubuntu_version}/ubuntu-${local.ubuntu_version}-live-server-amd64.iso"
  ubuntu_iso_checksum = "sha256:e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433"
}

variable "remote_host" {
  type        = string
  description = "XCP-ng pool primary (master) host IP or FQDN"
  sensitive   = true
}

variable "remote_username" {
  type        = string
  description = "XAPI username (typically root on the pool master)"
  sensitive   = true
  default     = "root"
}

variable "remote_password" {
  type        = string
  description = "XAPI password for the pool master"
  sensitive   = true
}

variable "sr_name" {
  type        = string
  description = "SR name_label where the builder VM disk is created"
  default     = "Local storage"
}

variable "sr_iso_name" {
  type        = string
  description = "ISO SR name_label used to store the Ubuntu installer ISO"
  default     = "Local ISO Store"
}

variable "tools_iso_name" {
  type        = string
  description = "VDI name_label for XCP-ng guest tools ISO (must exist on pool, e.g. SR \"XCP-ng tools\")"
  default     = "guest-tools.iso"
}

variable "clone_template" {
  type        = string
  description = "Diskless XCP-ng template for installer VM hardware (xe template-list)"
  default     = "Other install media"
}

variable "network_names" {
  type        = list(string)
  description = "XO network name_label(s) for the builder VM; empty uses pool default"
  default     = []
}

variable "vm_name" {
  type        = string
  description = "Template name_label created in Xen Orchestra / XCP-ng"
  default     = "ubuntu-24.04-golden"
}

variable "append_build_timestamp" {
  type        = bool
  description = "Append build timestamp to template name_label (unique name without packer -force). Update opentofu ubuntu_golden_template_name_label to match."
  default     = false
}

variable "vm_memory_mb" {
  type        = number
  description = "Memory for the temporary build VM (MiB)"
  default     = 2048
}

variable "disk_size_mb" {
  type        = number
  description = "Root disk size for the golden image (MiB)"
  default     = 15360
}

source "xenserver-iso" "ubuntu_2404" {
  iso_checksum = local.ubuntu_iso_checksum
  iso_url      = local.ubuntu_iso_url

  remote_host     = var.remote_host
  remote_username = var.remote_username
  remote_password = var.remote_password

  sr_name     = var.sr_name
  sr_iso_name = var.sr_iso_name

  clone_template = var.clone_template
  network_names  = var.network_names
  tools_iso_name = var.tools_iso_name
  firmware       = "uefi"
  ip_getter      = "tools"

  vm_name         = local.template_name_label
  vm_description  = "Ubuntu ${local.ubuntu_version} golden image (Packer ${local.timestamp})"
  vm_memory       = var.vm_memory_mb
  disk_size       = var.disk_size_mb
  vcpus_max       = 2
  vcpus_atstartup = 2
  vm_tags         = ["packer", "ubuntu-${local.ubuntu_version}", "golden"]

  boot_command = [
    "c<wait>",
    "set gfxpayload=keep<enter>",
    "linux /casper/vmlinuz autoinstall ---<enter>",
    "initrd /casper/initrd<enter>",
    "boot<enter>",
  ]

  cd_files = [
    "${path.root}/http/ubuntu-2404/user-data",
    "${path.root}/http/ubuntu-2404/meta-data",
  ]

  ssh_username           = "packer"
  ssh_password           = "ubuntu"
  ssh_wait_timeout       = "45m"
  ssh_handshake_attempts = 1000

  format            = "none"
  # "never" runs cleanup that destroys the VM after StepSetVmToTemplate — the template vanishes from XOA.
  keep_vm           = "on_success"
  skip_set_template = false
}

build {
  sources = ["source.xenserver-iso.ubuntu_2404"]

  provisioner "shell" {
    script          = "${path.root}/scripts/generalize-for-xcp-template.sh"
    execute_command = "echo ubuntu | sudo -S bash -c '{{ .Vars }} {{ .Path }}'"
  }
}
