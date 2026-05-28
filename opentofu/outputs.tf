output "local_iso_sr_id" {
  description = "Xen Orchestra ID for Local ISO Store (use as cdrom sr_id on VMs)"
  value       = data.xenorchestra_sr.local_iso.id
}

output "router_vm_id" {
  description = "Xen Orchestra ID for the router VM"
  value       = module.router.vm_id
}

output "router_dev_password" {
  description = "Password for the dev admin user (console / emergency login; SSH password auth disabled)"
  value       = random_password.dev.result
  sensitive   = true
}

output "router_wg_public_key" {
  description = "WireGuard server public key (use as [Peer] PublicKey on road-warrior clients)"
  value       = wireguard_asymmetric_key.router.public_key
}

output "router_pihole_password" {
  description = "Pi-hole web admin password"
  value       = random_password.pihole.result
  sensitive   = true
}