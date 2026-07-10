terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  subscription_id     = var.subscription_id
  storage_use_azuread = true
  features {}
}

# Phase 1 (network) outputs: RG, subnets, private DNS zones.
data "terraform_remote_state" "foundation" {
  backend = "local"
  config = {
    path = "../01-foundation/terraform.tfstate"
  }
}

# Phase 2 (observability) outputs: Application Insights connection string.
data "terraform_remote_state" "observability" {
  backend = "local"
  config = {
    path = "../02-observability/terraform.tfstate"
  }
}
