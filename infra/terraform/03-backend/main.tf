locals {
  foundation     = data.terraform_remote_state.foundation.outputs
  observability  = data.terraform_remote_state.observability.outputs
  prefix         = local.foundation.prefix
  location       = local.foundation.location
  location_short = local.foundation.location_short
  resource_group = local.foundation.resource_group_name
  tags           = local.foundation.tags
  subnet_ids     = local.foundation.subnet_ids
  dns_zone_ids   = local.foundation.private_dns_zone_ids
  appi_conn      = local.observability.application_insights_connection_string
}

# Random suffix for globally unique names (storage + function app hostname).
resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

########################################
# Storage account (backing the Function App)
# Shared key disabled (identity-based only) and no public network access.
########################################

resource "azurerm_storage_account" "this" {
  name                            = "st${local.prefix}${local.location_short}${random_string.suffix.result}"
  resource_group_name             = local.resource_group
  location                        = local.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  shared_access_key_enabled       = false
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"
  tags                            = local.tags
}

# Deployment package container for the Flex Consumption plan (managed-plane creation; no key needed).
resource "azurerm_storage_container" "deploy" {
  name                  = "app-package"
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

########################################
# Private endpoint — storage blob
########################################

resource "azurerm_private_endpoint" "storage_blob" {
  name                = "pe-${local.prefix}-st-blob"
  location            = local.location
  resource_group_name = local.resource_group
  subnet_id           = local.subnet_ids["private_endpoint"]
  tags                = local.tags

  private_service_connection {
    name                           = "psc-st-blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [local.dns_zone_ids["privatelink.blob.core.windows.net"]]
  }
}

########################################
# Flex Consumption Function App
########################################

resource "azurerm_service_plan" "this" {
  name                = "asp-${local.prefix}-${local.location_short}"
  resource_group_name = local.resource_group
  location            = local.location
  os_type             = "Linux"
  sku_name            = "FC1"
  tags                = local.tags
}

resource "azurerm_function_app_flex_consumption" "this" {
  name                = "func-${local.prefix}-${local.location_short}-${random_string.suffix.result}"
  resource_group_name = local.resource_group
  location            = local.location
  service_plan_id     = azurerm_service_plan.this.id

  storage_container_type      = "blobContainer"
  storage_container_endpoint  = "${azurerm_storage_account.this.primary_blob_endpoint}${azurerm_storage_container.deploy.name}"
  storage_authentication_type = "SystemAssignedIdentity"

  runtime_name    = "node"
  runtime_version = var.node_version

  instance_memory_in_mb  = 2048
  maximum_instance_count = 40

  https_only                    = true
  public_network_access_enabled = var.function_public_network_access_enabled
  virtual_network_subnet_id     = local.subnet_ids["function"]

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_insights_connection_string = local.appi_conn
  }

  app_settings = {
    # Identity-based AzureWebJobsStorage (no keys); resolves privately via the blob PE.
    AzureWebJobsStorage__accountName = azurerm_storage_account.this.name
  }
}

########################################
# RBAC — Function identity to storage (runtime state + deployment package)
########################################

resource "azurerm_role_assignment" "func_blob_owner" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_function_app_flex_consumption.this.identity[0].principal_id
}

########################################
# Private endpoint — Function App (inbound)
########################################

resource "azurerm_private_endpoint" "function_site" {
  name                = "pe-${local.prefix}-func-site"
  location            = local.location
  resource_group_name = local.resource_group
  subnet_id           = local.subnet_ids["private_endpoint"]
  tags                = local.tags

  private_service_connection {
    name                           = "psc-func-site"
    private_connection_resource_id = azurerm_function_app_flex_consumption.this.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "sites"
    private_dns_zone_ids = [local.dns_zone_ids["privatelink.azurewebsites.net"]]
  }
}
