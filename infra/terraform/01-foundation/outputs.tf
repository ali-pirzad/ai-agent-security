output "resource_group_name" {
  description = "Name of the demo resource group."
  value       = azurerm_resource_group.this.name
}

output "location" {
  description = "Azure region."
  value       = azurerm_resource_group.this.location
}

output "location_short" {
  description = "Short region token used in resource names."
  value       = var.location_short
}

output "prefix" {
  description = "Resource-name prefix."
  value       = var.prefix
}

output "vnet_id" {
  description = "Virtual network resource ID."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Virtual network name."
  value       = azurerm_virtual_network.this.name
}

output "subnet_ids" {
  description = "Map of subnet name to resource ID."
  value = {
    apim             = azurerm_subnet.apim.id
    function         = azurerm_subnet.function.id
    private_endpoint = azurerm_subnet.private_endpoint.id
    agent            = azurerm_subnet.agent.id
  }
}

output "private_dns_zone_ids" {
  description = "Map of private DNS zone name to resource ID."
  value       = { for name, zone in azurerm_private_dns_zone.this : name => zone.id }
}

output "tags" {
  description = "Common tags."
  value       = var.tags
}
