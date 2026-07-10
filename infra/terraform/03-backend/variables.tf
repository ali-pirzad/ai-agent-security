variable "subscription_id" {
  type        = string
  description = "Azure subscription ID to deploy the demo into."
}

variable "function_public_network_access_enabled" {
  type        = bool
  description = "Whether the Function App is reachable from the public internet. Keep true for the initial code deploy (SCM must be reachable), then set false to lock down to private endpoint only."
  default     = true
}

variable "node_version" {
  type        = string
  description = "Node.js runtime version for the Function App."
  default     = "20"
}
