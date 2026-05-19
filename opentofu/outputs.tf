output "local_iso_sr_id" {
  description = "Xen Orchestra ID for Local ISO Store (use as cdrom sr_id on VMs)"
  value       = data.xenorchestra_sr.local_iso.id
}