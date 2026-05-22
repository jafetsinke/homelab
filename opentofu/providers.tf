terraform {
  required_version = ">= 1.6.0"

  required_providers {
    xenorchestra = {
      source  = "registry.opentofu.org/vatesfr/xenorchestra"
      version = "~> 0.26"
    }
    random = {
      source  = "registry.opentofu.org/hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "xenorchestra" {
  url      = var.xo_url
  username = var.xo_username
  password = var.xo_password
  insecure = var.xo_insecure
}
