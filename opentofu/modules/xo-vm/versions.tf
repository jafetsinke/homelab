terraform {
  required_version = ">= 1.6.0"

  required_providers {
    xenorchestra = {
      source  = "registry.opentofu.org/vatesfr/xenorchestra"
      version = ">= 0.26"
    }
    null = {
      source  = "registry.opentofu.org/hashicorp/null"
      version = ">= 3.2"
    }
    external = {
      source  = "registry.opentofu.org/hashicorp/external"
      version = ">= 2.3"
    }
  }
}
