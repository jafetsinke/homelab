variable "xo_url" {
  description = "Xen Orchestra WebSocket URL (ws:// or wss://host)"
  type        = string
}
variable "xo_username" {
  description = "Xen Orchestra username (ignored when xo_token is set)"
  type        = string
}

variable "xo_password" {
  description = "Xen Orchestra password (ignored when xo_token is set)"
  type        = string
  sensitive   = true
}

variable "xo_insecure" {
  description = "Skip TLS verification for Xen Orchestra (homelab/self-signed certs only)"
  type        = bool
  default     = false
}