output "vm_id" {
  description = "XO VM UUID."
  value       = xenorchestra_vm.this.id
}

output "persistent_vdi_ids" {
  description = "Persistent data VDI UUIDs keyed by persistent disk name."
  value = {
    for key, lookup in data.external.persistent_vdi :
    key => lookup.result["vdi_id"] != "" ? lookup.result["vdi_id"] : null
  }
}

output "cloud_config_id" {
  description = "XO cloud-config object UUID."
  value       = xenorchestra_cloud_config.this.id
}
