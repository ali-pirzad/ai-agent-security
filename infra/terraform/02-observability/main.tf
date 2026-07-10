locals {
  foundation     = data.terraform_remote_state.foundation.outputs
  prefix         = local.foundation.prefix
  location       = local.foundation.location
  location_short = local.foundation.location_short
  resource_group = local.foundation.resource_group_name
  tags           = local.foundation.tags
}

########################################
# Log Analytics workspace
# Central log sink for APIM diagnostics (Phase 4) and AI Foundry agent tracing (Phase 5).
########################################

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${local.prefix}-${local.location_short}"
  location            = local.location
  resource_group_name = local.resource_group
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

########################################
# Application Insights (workspace-based)
# Shared APM/trace store. APIM sends gateway telemetry here; Foundry sends agent traces here.
########################################

resource "azurerm_application_insights" "this" {
  name                = "appi-${local.prefix}-${local.location_short}"
  location            = local.location
  resource_group_name = local.resource_group
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  tags                = local.tags
}
