data "xenorchestra_host" "xcp_ng_01" {
  name_label = "xcp-ng-01"
}

data "xenorchestra_sr" "local_iso" {
  name_label = "Local ISO Store"
  pool_id    = data.xenorchestra_host.xcp_ng_01.pool_id
}