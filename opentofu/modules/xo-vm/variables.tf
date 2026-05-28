variable "hostname" {
  type        = string
  description = "Guest hostname and VM name label in Xen Orchestra."
}

variable "template_id" {
  type        = string
  description = "XO template UUID to clone."
}

variable "xo_auth" {
  type = object({
    url      = optional(string)
    token    = optional(string)
    insecure = optional(bool, false)
  })
  description = "Optional XO API token/settings for helper scripts. All fields optional."
}

variable "network_id" {
  type        = string
  description = "Network UUID for the primary VIF."
}

variable "sr_id" {
  type        = string
  description = "Default storage repository UUID for the root disk and persistent disks."
}

variable "resources" {
  type = object({
    cpus          = number
    memory_max_mb = number
    root_disk_gb  = number
    swap_size_mb  = optional(number)
  })
  description = "Compute, root disk sizing, and swap settings for the VM."
}

variable "cloud_config" {
  type = object({
    users = list(object({
      name     = string
      password = optional(string)
      sudo     = optional(bool, false)
      ssh_keys = optional(list(string), [])
    }))
    packages = list(string)
    write_files = list(object({
      path        = string
      content     = string
      permissions = optional(string)
    }))
    runcmd = list(string)
  })
  description = "Cloud-init sections merged into the module default cloud-config."
}

variable "network" {
  type = object({
    ipv4_address = optional(string)
    gateway      = optional(string)
    nameservers  = optional(list(string), [])
  })
  default     = null
  description = "Optional static IPv4 settings rendered into cloud-init network-config v2."
}

variable "persistent_disks" {
  type = list(object({
    name       = string
    size_gb    = number
    sr_id      = optional(string)
    name_label = optional(string)
    position   = optional(string)
  }))
  default     = []
  description = "Extra data disks managed outside xenorchestra_vm.disk (persistent across VM replacement)."

  validation {
    condition     = length(var.persistent_disks) == length(distinct([for disk in var.persistent_disks : disk.name]))
    error_message = "Each persistent disk name must be unique."
  }
}

variable "name_description" {
  type        = string
  default     = null
  description = "Optional VM description."
}

variable "clone_type" {
  type        = string
  default     = null
  description = "Optional clone type (for example full)."
}

variable "hvm_boot_firmware" {
  type        = string
  default     = "uefi"
  description = "HVM boot firmware to use for the VM."
}

variable "tags" {
  type        = list(string)
  default     = null
  description = "Optional VM tags."
}

variable "auto_poweron" {
  type        = bool
  default     = true
  description = "XO auto-power-on flag (VM start is handled after persistent disk attach)."
}

variable "timeouts_create" {
  type        = string
  default     = "5m"
  description = "Create timeout for xenorchestra_vm."
}
