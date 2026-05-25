output "vm_id" {
  description = "XO VM UUID."
  value       = xenorchestra_vm.this.id
}

output "vm_ipv4_addresses" {
  description = "IPv4 addresses on the primary VIF."
  value       = xenorchestra_vm.this.network[0].ipv4_addresses
}

output "persistent_vdi_ids" {
  description = "Persistent data VDI UUIDs keyed by persistent disk name."
  value = {
    for key, lookup in data.external.persistent_vdi : key => lookup.result["vdi_id"]
  }
}

output "cloud_config_id" {
  description = "XO cloud-config object UUID."
  value       = xenorchestra_cloud_config.this.id
}
