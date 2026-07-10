# Setup providers
#
# Single-subscription adaptation: this project deploys everything into ONE
# subscription (22d921af-...), so every aliased provider below points at the
# same subscription. The resource aliases (workload_subscription /
# infra_subscription) are preserved because the resources reference them, but
# subscription_id_resources == subscription_id_infra in terraform.tfvars.
provider "azapi" {
  subscription_id = var.subscription_id_resources
}

provider "azapi" {
  alias           = "workload_subscription"
  subscription_id = var.subscription_id_resources
}

provider "azapi" {
  alias           = "infra_subscription"
  subscription_id = var.subscription_id_infra
}

provider "azurerm" {
  subscription_id     = var.subscription_id_resources
  features {}
  storage_use_azuread = true
}

provider "azurerm" {
  alias               = "workload_subscription"
  subscription_id     = var.subscription_id_resources
  features {}
  storage_use_azuread = true
}

provider "azurerm" {
  alias               = "infra_subscription"
  subscription_id     = var.subscription_id_infra
  features {}
  storage_use_azuread = true
}
