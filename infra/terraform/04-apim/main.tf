locals {
  foundation     = data.terraform_remote_state.foundation.outputs
  observability  = data.terraform_remote_state.observability.outputs
  backend        = data.terraform_remote_state.backend.outputs
  prefix         = local.foundation.prefix
  location       = local.foundation.location
  location_short = local.foundation.location_short
  resource_group = local.foundation.resource_group_name
  tags           = local.foundation.tags
  apim_subnet_id = local.foundation.subnet_ids["apim"]

  # Private Function App backend (reachable only from inside the VNet).
  function_base_url = "https://${local.backend.function_app_default_hostname}"
}

resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

########################################
# Public IP (required for APIM stv2 VNet injection)
########################################

resource "azurerm_public_ip" "apim" {
  name                = "pip-${local.prefix}-apim-${local.location_short}"
  resource_group_name = local.resource_group
  location            = local.location
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "apim-${local.prefix}-${local.location_short}-${random_string.suffix.result}"
  tags                = local.tags

  # The connectivity subscription's governance policy stamps ip_tags onto public IPs
  # after creation. Ignore that drift so Terraform doesn't try to remove them (which
  # would force replacement of the in-use IP and the whole APIM instance).
  lifecycle {
    ignore_changes = [ip_tags]
  }
}

########################################
# API Management (Developer, VNet External injection)
# Public gateway (so Copilot Studio / Foundry can reach it), private backend.
########################################

resource "azurerm_api_management" "this" {
  name                 = "apim-${local.prefix}-${local.location_short}-${random_string.suffix.result}"
  resource_group_name  = local.resource_group
  location             = local.location
  publisher_name       = var.publisher_name
  publisher_email      = var.publisher_email
  sku_name             = var.apim_sku
  virtual_network_type = "External"
  public_ip_address_id = azurerm_public_ip.apim.id
  tags                 = local.tags

  identity {
    type = "SystemAssigned"
  }

  virtual_network_configuration {
    subnet_id = local.apim_subnet_id
  }
}

########################################
# Welcome API (public landing at the gateway root)
########################################

resource "azurerm_api_management_api" "welcome" {
  name                  = "welcome-api"
  resource_group_name   = local.resource_group
  api_management_name   = azurerm_api_management.this.name
  revision              = "1"
  display_name          = "Welcome"
  path                  = ""
  protocols             = ["https"]
  service_url           = local.function_base_url
  subscription_required = false
}

resource "azurerm_api_management_api_operation" "welcome_get" {
  operation_id        = "welcome-get"
  api_name            = azurerm_api_management_api.welcome.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = local.resource_group
  display_name        = "Welcome"
  method              = "GET"
  url_template        = "/"
  response {
    status_code = 200
  }
}

resource "azurerm_api_management_api_policy" "welcome" {
  api_name            = azurerm_api_management_api.welcome.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = local.resource_group
  xml_content         = file("${path.module}/../policies/welcome-api.xml")
}

########################################
# Customer API (subscription-key protected, rate-limited, validated)
########################################

resource "azurerm_api_management_api" "customer" {
  name                  = "customer-api"
  resource_group_name   = local.resource_group
  api_management_name   = azurerm_api_management.this.name
  revision              = "1"
  display_name          = "Customer API"
  path                  = "api"
  protocols             = ["https"]
  service_url           = local.function_base_url
  subscription_required = true
}

resource "azurerm_api_management_api_operation" "customer_get" {
  operation_id        = "get-customer"
  api_name            = azurerm_api_management_api.customer.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = local.resource_group
  display_name        = "Get customer by id"
  method              = "GET"
  url_template        = "/customer/{id}"
  description         = "Returns a mock customer record (customerId, riskScore, riskTier, transactions)."

  template_parameter {
    name     = "id"
    required = true
    type     = "string"
  }

  response {
    status_code = 200
  }
}

resource "azurerm_api_management_api_policy" "customer" {
  api_name            = azurerm_api_management_api.customer.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = local.resource_group
  xml_content         = file("${path.module}/../policies/customer-api.xml")
}

########################################
# Subscription key for the Customer API (demo client credential)
########################################

resource "azurerm_api_management_subscription" "customer" {
  api_management_name = azurerm_api_management.this.name
  resource_group_name = local.resource_group
  # Scope to all APIs (omitting api_id/product_id). Scoping to api_id pins the
  # subscription to the API *revision* (/apis/customer-api;rev=1), which the gateway
  # does not match at runtime -> every key is rejected as invalid.
  display_name  = "aas-demo-client"
  state         = "active"
  allow_tracing = true
}

########################################
# Observability — APIM -> Application Insights
########################################

resource "azurerm_api_management_logger" "appi" {
  name                = "appi-logger"
  api_management_name = azurerm_api_management.this.name
  resource_group_name = local.resource_group
  resource_id         = local.observability.application_insights_id

  application_insights {
    instrumentation_key = local.observability.application_insights_instrumentation_key
  }
}

resource "azurerm_api_management_diagnostic" "appi" {
  identifier               = "applicationinsights"
  api_management_name      = azurerm_api_management.this.name
  resource_group_name      = local.resource_group
  api_management_logger_id = azurerm_api_management_logger.appi.id

  sampling_percentage       = 100
  always_log_errors         = true
  log_client_ip             = true
  verbosity                 = "information"
  http_correlation_protocol = "W3C"

  frontend_request {
    body_bytes = 1024
  }
  frontend_response {
    body_bytes = 1024
  }
  backend_request {
    body_bytes = 1024
  }
  backend_response {
    body_bytes = 1024
  }
}
