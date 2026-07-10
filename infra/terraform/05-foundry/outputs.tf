output "foundry_account_name" {
  description = "The name of the AI Foundry (Cognitive Services) account"
  value       = azapi_resource.ai_foundry.name
}

output "foundry_account_id" {
  description = "The resource id of the AI Foundry account"
  value       = azapi_resource.ai_foundry.id
}

output "foundry_account_endpoint" {
  description = "The AI Foundry account endpoint (from properties.endpoint)"
  value       = try(azapi_resource.ai_foundry.output.properties.endpoint, null)
}

output "project_name" {
  description = "The name of the AI Foundry project"
  value       = azapi_resource.ai_foundry_project.name
}

output "project_id" {
  description = "The resource id of the AI Foundry project"
  value       = azapi_resource.ai_foundry_project.id
}
