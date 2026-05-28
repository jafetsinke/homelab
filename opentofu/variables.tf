variable "xo_url" {
  description = "Xen Orchestra WebSocket URL (ws:// or wss://host)"
  type        = string
}
variable "xo_token" {
  description = "Xen Orchestra API token"
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
}

variable "xo_insecure" {
  description = "Skip TLS verification for Xen Orchestra (homelab/self-signed certs only)"
  type        = bool
  default     = false
}