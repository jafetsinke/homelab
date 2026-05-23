locals {
  admin_username = "dev"

  # Privileged SSH-only users (no password login).
  users = [
    {
      name     = "jafet"
      ssh_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILJACyn3F6FS7xdGcSSEbJEkEvK4QzaQ/FnRMCm1aQo3 Jafet-MBP"]
    },
  ]

  setup_data_disk_script = file("${path.module}/scripts/setup-data-disk.sh")
}
