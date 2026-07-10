variable "subscription_id" {
  type        = string
  description = "Azure subscription ID to deploy the demo into."
}

variable "publisher_name" {
  type        = string
  description = "APIM publisher/organization name."
  default     = "AI Agents Security Demo"
}

variable "publisher_email" {
  type        = string
  description = "APIM publisher email (receives notifications)."
  default     = "alipirzad@microsoft.com"
}

variable "apim_sku" {
  type        = string
  description = "APIM SKU. Developer_1 for the demo (VNet-injectable, non-production)."
  default     = "Developer_1"
}
