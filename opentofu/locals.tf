locals {
  admin_username = "dev"

  users = [
    {
      name     = "jafet"
      sudo     = true
      ssh_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILJACyn3F6FS7xdGcSSEbJEkEvK4QzaQ/FnRMCm1aQo3 Jafet-MBP"]
    },
  ]

  xo_auth = {
    url      = var.xo_url
    token    = var.xo_token
    insecure = var.xo_insecure
  }
}
