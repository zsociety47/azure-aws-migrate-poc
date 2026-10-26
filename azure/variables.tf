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
  description = "Name of the discovery appliance virtual machine."
  type        = string
  default     = "vm-appl-zeon"
}

variable "discovery_virtual_machine_size" {
  description = "Size of the discovery appliance. Standard_D8as_v4 is 8 vCPU and 32 GB, which is the appliance minimum, and this subscription has quota for that family in East US."
  type        = string
  default     = "Standard_D8as_v4"
}

variable "discovery_os_disk_name" {
  description = "Name of the operating-system disk on the discovery appliance."
  type        = string
  default     = "osdisk-appl-zeon"
}

variable "discovery_admin_username" {
  description = "Local administrator on the discovery appliance. This is the sign-in for that virtual machine, not the account on the source server."
  type        = string
  default     = "migrateadmin"
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

variable "discovery_public_ip_name" {
  description = "Name of the public IP address on the discovery appliance. The network interface attaches it."
  type        = string
  default     = "pip-appl-zeon"
}

variable "discovery_network_interface_name" {
  description = "Name of the network interface on the discovery appliance. It joins the public address to the subnet."
  type        = string
  default     = "nic-appl-zeon"
}

variable "discovery_admin_password" {
  description = "Password for the local administrator on the discovery appliance. It has no default, so it is typed at plan time and is not saved in this file. At least 12 characters, with an uppercase letter, a lowercase letter, a number, and a symbol."
  type        = string
  sensitive   = true

  validation {
    condition = (
      length(var.discovery_admin_password) >= 12 &&
      length(var.discovery_admin_password) <= 123 &&
      length(regexall("[A-Z]", var.discovery_admin_password)) > 0 &&
      length(regexall("[a-z]", var.discovery_admin_password)) > 0 &&
      length(regexall("[0-9]", var.discovery_admin_password)) > 0 &&
      length(regexall("[^A-Za-z0-9]", var.discovery_admin_password)) > 0 &&
      !strcontains(var.discovery_admin_password, "\"") &&
      !strcontains(var.discovery_admin_password, "$") &&
      !strcontains(var.discovery_admin_password, "`") &&
      !strcontains(lower(var.discovery_admin_password), lower(var.discovery_admin_username))
    )
    error_message = "Use 12 to 123 characters, with an uppercase letter, a lowercase letter, a number, and a symbol. Do not include a double quote, a dollar sign, a backtick, or the username."
  }
}

variable "tags" {
  description = "Base tags. lifetime and created are added in tags.tf. project is the folder name."
  type        = map(string)
  default = {
    project     = "06-aws-to-azure-migrate-poc"
    environment = "poc"
    managed-by  = "terraform"
    owner       = "zeon"
  }
}
