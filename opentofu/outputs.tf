output "local_iso_sr_id" {
  description = "Xen Orchestra ID for Local ISO Store (use as cdrom sr_id on VMs)"
  value       = data.xenorchestra_sr.local_iso.id
}

output "router_vm_id" {
  description = "Xen Orchestra ID for the router VM"
  value       = xenorchestra_vm.router.id
}

output "router_ipv4_addresses" {
  description = "IPv4 addresses on the router VM (requires guest tools after install)"
  value       = xenorchestra_vm.router.network[0].ipv4_addresses
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