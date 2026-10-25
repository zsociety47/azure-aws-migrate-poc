# Names, addresses, and tags for the Azure side.
# The provider is already configured. Resource files read these values
# so a name is written once and reused everywhere.
#
# Azure has no region on the provider. Each resource uses location.
# 10.6.0.0/16 stays clear of the Amazon Web Services (AWS) network
# 10.0.0.0/16 and of the other project's 10.1.0.0/16.

variable "location" {
  description = "Azure region for every resource in this build."
  type        = string
  default     = "East US"
}

variable "staging_resource_group_name" {
  description = "Resource group for the Migrate project and the discovery appliance."
  type        = string
  default     = "rg-migrate-src-zeon01"
}

variable "target_resource_group_name" {
  description = "Resource group the migrated server lands in."
  type        = string
  default     = "rg-migrate-tgt-zeon01"
}

variable "virtual_network_name" {
  description = "Name of the virtual network."
  type        = string
  default     = "vnet-migrate-zeon"
}

variable "virtual_network_cidr" {
  description = "Address space of the virtual network. The subnet prefix must fit inside it."
  type        = string
  default     = "10.6.0.0/16"
}

variable "subnet_name" {
  description = "Name of the subnet that holds the discovery appliance and the migrated server."
  type        = string
  default     = "snet-migrate"
}

variable "subnet_cidr" {
  description = "Address prefix of the subnet. This is a slice of the virtual network address space."
  type        = string
  default     = "10.6.1.0/24"
}

variable "network_security_group_name" {
  description = "Name of the firewall on the subnet."
  type        = string
  default     = "nsg-migrate-tgt-zeon"
}

variable "discovery_virtual_machine_name" {
  description = "Name of the discovery appliance virtual machine. The virtual machine file comes later."
  type        = string
  default     = "vm-appl-zeon"
}

variable "discovery_computer_name" {
  description = "Windows computer name of the discovery appliance. 15 characters is the maximum."
  type        = string
  default     = "appl-zeon"
}

variable "discovery_appliance_name" {
  description = "Name typed into the Azure Migrate portal for the discovery appliance. Letters and numbers only, 14 characters maximum."
  type        = string
  default     = "migapplzeon01"
}

variable "tags" {
  description = "Tags on every Azure resource in this build."
  type        = map(string)
  default = {
    project     = "azure-aws-migrate-poc"
    environment = "poc"
    managed-by  = "terraform"
    owner       = "zeon"
  }
}
