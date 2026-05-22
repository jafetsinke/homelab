data "xenorchestra_host" "shiitake" {
  name_label = "shiitake"
}

data "xenorchestra_sr" "local_iso" {
  name_label = "Local ISO Store"
  pool_id    = data.xenorchestra_host.shiitake.pool_id
}

data "xenorchestra_pif" "eth0" {
  device  = "eth0"
  vlan    = -1
  host_id = data.xenorchestra_host.shiitake.id
}

data "xenorchestra_sr" "default" {
  name_label = "Local storage"
  pool_id    = data.xenorchestra_host.shiitake.pool_id
}

data "xenorchestra_template" "ubuntu_2404_golden" {
  name_label = "ubuntu-24.04-golden"
  pool_id    = data.xenorchestra_host.shiitake.pool_id
}
