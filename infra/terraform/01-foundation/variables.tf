variable "subscription_id" {
  type        = string
  description = "Azure subscription ID to deploy the demo into."
}

variable "prefix" {
  type        = string
  description = "Short project prefix used for all resource names."
  default     = "aas"
}

variable "location" {
  type        = string
  description = "Azure region for all resources."
  default     = "centralus"
}

variable "location_short" {
  type        = string
  description = "Short region token used in resource names."
  default     = "cus"
}

variable "vnet_address_space" {
  type        = string
  description = "VNet CIDR. Class C (192.168.0.0/16) because centralus is not in the 10.x supported list for the Foundry network-isolated agent."
  default     = "192.168.0.0/16"
}

variable "subnet_prefixes" {
  type = object({
    apim             = string
    function         = string
    private_endpoint = string
    agent            = string
  })
  description = "Per-subnet CIDR ranges carved from the VNet address space."
  default = {
    apim             = "192.168.1.0/24"
    function         = "192.168.2.0/24"
    private_endpoint = "192.168.3.0/24"
    agent            = "192.168.4.0/24"
  }
}

variable "ddos_policy_assignment_id" {
  type        = string
  description = "ID of the Enable-DDoS-VNET policy assignment (inherited from the connectivity management group) to exempt this resource group from, so VNet creation is not blocked by the missing DDoS plan."
  default     = "/providers/Microsoft.Management/managementGroups/connectivity/providers/Microsoft.Authorization/policyAssignments/Enable-DDoS-VNET"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to every resource."
  default = {
    project     = "aas"
    environment = "demo"
    purpose     = "ai-agents-security"
  }
}
