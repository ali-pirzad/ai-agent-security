########################################
# Resource Group
########################################

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.prefix}-demo-${var.location_short}"
  location = var.location
  tags     = var.tags
}

########################################
# Policy exemption — Enable-DDoS-VNET
# The connectivity management group assigns a Modify policy that force-attaches a
# (non-existent) DDoS Protection Plan to every VNet, which blocks VNet creation.
# This Waiver exempts only the demo resource group. The demo does not require DDoS.
########################################

resource "azurerm_resource_group_policy_exemption" "ddos" {
  name                 = "exempt-${var.prefix}-ddos"
  resource_group_id    = azurerm_resource_group.this.id
  policy_assignment_id = var.ddos_policy_assignment_id
  exemption_category   = "Waiver"
  display_name         = "Exempt ${var.prefix} demo RG from Enable-DDoS-VNET"
  description          = "Demo environment does not require Azure DDoS Network Protection; the assigned plan does not exist and blocks VNet creation."
}

########################################
# Virtual Network
########################################

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.prefix}-${var.location_short}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_address_space]
  tags                = var.tags

  # Ensure the DDoS policy exemption exists before the VNet is created.
  depends_on = [azurerm_resource_group_policy_exemption.ddos]
}

# APIM subnet (stv2 External injection — public gateway, private backend). No delegation.
resource "azurerm_subnet" "apim" {
  name                 = "snet-apim"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_prefixes.apim]
}

# Function App regional VNet integration subnet.
# Delegated to Microsoft.App/environments because the backend runs on the Azure Functions
# Flex Consumption plan, whose VNet integration requires this delegation (Premium/Dedicated
# plans use Microsoft.Web/serverFarms instead). Must be >= /27 and not host private endpoints.
resource "azurerm_subnet" "function" {
  name                 = "snet-function"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_prefixes.function]

  delegation {
    name = "flex-delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Private Endpoint subnet — hosts private endpoints for backend + Foundry dependencies.
resource "azurerm_subnet" "private_endpoint" {
  name                 = "snet-private-endpoint"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_prefixes.private_endpoint]
}

# Agent subnet — delegated to Microsoft.App/environments for the Foundry Standard Agent.
resource "azurerm_subnet" "agent" {
  name                 = "snet-agent"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_prefixes.agent]

  delegation {
    name = "agent-delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

########################################
# NSG — APIM subnet (required rules for stv2 External VNet injection)
########################################

resource "azurerm_network_security_group" "apim" {
  name                = "nsg-${var.prefix}-apim-${var.location_short}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  # --- Inbound ---
  security_rule {
    name                       = "AllowClientHTTPS"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowApimManagement"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3443"
    source_address_prefix      = "ApiManagement"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowAzureLoadBalancer"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6390"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "VirtualNetwork"
  }

  # --- Outbound (APIM dependencies) ---
  security_rule {
    name                       = "AllowStorageOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Storage"
  }

  security_rule {
    name                       = "AllowSqlOutbound"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1433"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "SQL"
  }

  security_rule {
    name                       = "AllowKeyVaultOutbound"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureKeyVault"
  }

  security_rule {
    name                       = "AllowMonitorOutbound"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["1886", "443"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureMonitor"
  }
}

resource "azurerm_subnet_network_security_group_association" "apim" {
  subnet_id                 = azurerm_subnet.apim.id
  network_security_group_id = azurerm_network_security_group.apim.id
}

########################################
# NSG — Function subnet (deny-by-default egress demo)
########################################

resource "azurerm_network_security_group" "function" {
  name                = "nsg-${var.prefix}-func-${var.location_short}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  # Allow intra-VNet traffic (reach private endpoints for storage/backend).
  security_rule {
    name                       = "AllowVnetOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # Deny all direct outbound internet — proves no uncontrolled egress from the backend.
  security_rule {
    name                       = "DenyInternetOutbound"
    priority                   = 4096
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

resource "azurerm_subnet_network_security_group_association" "function" {
  subnet_id                 = azurerm_subnet.function.id
  network_security_group_id = azurerm_network_security_group.function.id
}

########################################
# Private DNS zones (backend + Foundry dependencies) + VNet links
########################################

locals {
  private_dns_zones = [
    "privatelink.azurewebsites.net",           # Function App
    "privatelink.blob.core.windows.net",       # Storage (blob)
    "privatelink.cognitiveservices.azure.com", # Foundry / Cognitive Services
    "privatelink.openai.azure.com",            # Azure OpenAI
    "privatelink.services.ai.azure.com",       # AI Services / Foundry
    "privatelink.search.windows.net",          # AI Search
    "privatelink.documents.azure.com",         # Cosmos DB (SQL)
  ]
}

resource "azurerm_private_dns_zone" "this" {
  for_each            = toset(local.private_dns_zones)
  name                = each.value
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each              = azurerm_private_dns_zone.this
  name                  = "link-${replace(each.value.name, ".", "-")}"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = each.value.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}
