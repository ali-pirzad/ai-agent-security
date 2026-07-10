output "apim_name" {
  description = "APIM instance name."
  value       = azurerm_api_management.this.name
}

output "apim_gateway_url" {
  description = "APIM gateway base URL (the customer-facing entrypoint)."
  value       = azurerm_api_management.this.gateway_url
}

output "welcome_url" {
  description = "Public welcome landing (no key)."
  value       = azurerm_api_management.this.gateway_url
}

output "customer_url_example" {
  description = "Example customer call (append ?subscription-key=... )."
  value       = "${azurerm_api_management.this.gateway_url}/api/customer/ACME-42"
}

output "customer_subscription_key" {
  description = "Subscription key for the Customer API (demo client credential)."
  value       = azurerm_api_management_subscription.customer.primary_key
  sensitive   = true
}
