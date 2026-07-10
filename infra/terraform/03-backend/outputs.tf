output "function_app_name" {
  description = "Name of the Flex Consumption Function App."
  value       = azurerm_function_app_flex_consumption.this.name
}

output "function_app_id" {
  description = "Resource ID of the Function App."
  value       = azurerm_function_app_flex_consumption.this.id
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App (resolves to the private endpoint inside the VNet)."
  value       = azurerm_function_app_flex_consumption.this.default_hostname
}

output "function_app_principal_id" {
  description = "System-assigned managed identity principal ID of the Function App."
  value       = azurerm_function_app_flex_consumption.this.identity[0].principal_id
}

output "storage_account_name" {
  description = "Backing storage account name."
  value       = azurerm_storage_account.this.name
}

output "resource_group_name" {
  description = "Resource group name (passthrough for later phases)."
  value       = local.resource_group
}
