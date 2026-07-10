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
  subscription_id = var.subscription_id
  features {}
}

data "terraform_remote_state" "foundation" {
  backend = "local"
  config  = { path = "../01-foundation/terraform.tfstate" }
}

data "terraform_remote_state" "observability" {
  backend = "local"
  config  = { path = "../02-observability/terraform.tfstate" }
}

data "terraform_remote_state" "backend" {
  backend = "local"
  config  = { path = "../03-backend/terraform.tfstate" }
}
