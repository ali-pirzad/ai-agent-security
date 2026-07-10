variable "subscription_id" {
  type        = string
  description = "Azure subscription ID to deploy the demo into."
}

variable "log_retention_days" {
  type        = number
  description = "Retention in days for the Log Analytics workspace."
  default     = 30
}
