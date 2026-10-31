# Names and sizes for the replication appliance when it lives in Azure.
# The AWS source stays in aws/. This folder does not create it.

variable "location" {
  description = "Azure region for every resource in this folder."
  type        = string
  default     = "East US"
}

variable "resource_group_name" {
  description = "Resource group for the replication appliance. It bills by the hour, so it carries lifetime=1d."
  type        = string
  default     = "rg-migrate-repl-zeon01"
}

variable "virtual_network_name" {
  description = "Name of the virtual network. The address space stays clear of the AWS network and of the discovery network."
  type        = string
  default     = "vnet-repl-zeon"
}

variable "virtual_network_cidr" {
  description = "Address space of the virtual network. 10.0.0.0/16 is the AWS source. 10.6.0.0/16 is the discovery network."
  type        = string
  default     = "10.7.0.0/16"
}

variable "subnet_name" {
  description = "Name of the subnet that holds the replication appliance."
  type        = string
  default     = "snet-repl"
}

variable "subnet_cidr" {
  description = "Address prefix of the subnet. This is a slice of the virtual network address space."
  type        = string
  default     = "10.7.1.0/24"
}

variable "network_security_group_name" {
  description = "Name of the firewall on the subnet."
  type        = string
  default     = "nsg-repl"
}

variable "replication_virtual_machine_name" {
  description = "Name of the replication appliance virtual machine."
  type        = string
  default     = "vm-repl"
}

variable "replication_virtual_machine_size" {
  description = "Size of the replication appliance. Standard_D8ds_v4 is 8 virtual CPUs and 32 GB (Intel) with a temporary disk. Standard_D8as_v4 has a temporary disk, so a resize cannot drop it. East US had no capacity for Standard_D8s_v3. Standard_D8s_v4 was refused because it has no temporary disk. Standard_D8as_v4 reports 4 guest cores and Azure Site Recovery refuses it."
  type        = string
  default     = "Standard_D8ds_v4"
}

variable "replication_computer_name" {
  description = "Windows computer name of the replication appliance. 15 characters is the maximum."
  type        = string
  default     = "repl-zeon"
}

variable "replication_admin_username" {
  description = "Local administrator on the replication appliance. This is the sign-in for that virtual machine."
  type        = string
  default     = "migrateadmin"
}

variable "replication_admin_password" {
  description = "Password for the local administrator. It has no default and it is not stored in a tfvars file. Set TF_VAR_replication_admin_password in the environment for the plan. At least 12 characters, with an uppercase letter, a lowercase letter, a number, and a symbol."
  type        = string
  sensitive   = true

  validation {
    condition = (
      length(var.replication_admin_password) >= 12 &&
      length(var.replication_admin_password) <= 123 &&
      length(regexall("[A-Z]", var.replication_admin_password)) > 0 &&
      length(regexall("[a-z]", var.replication_admin_password)) > 0 &&
      length(regexall("[0-9]", var.replication_admin_password)) > 0 &&
      length(regexall("[^A-Za-z0-9]", var.replication_admin_password)) > 0 &&
      !strcontains(var.replication_admin_password, "\"") &&
      !strcontains(var.replication_admin_password, "$") &&
      !strcontains(var.replication_admin_password, "`") &&
      !strcontains(lower(var.replication_admin_password), lower(var.replication_admin_username))
    )
    error_message = "Use 12 to 123 characters, with an uppercase letter, a lowercase letter, a number, and a symbol. Do not include a double quote, a dollar sign, a backtick, or the username."
  }
}

variable "replication_os_disk_name" {
  description = "Name of the operating-system disk. The Windows image requires 127 GB."
  type        = string
  default     = "osdisk-repl"
}

variable "replication_cache_disk_name" {
  description = "Name of the cache disk. The appliance requires at least 600 GB, left unformatted for the installer."
  type        = string
  default     = "disk-repl-cache"
}

variable "replication_cache_disk_size_gb" {
  description = "Cache disk size in gibibytes. 620 matches the AWS cache disk in variant A."
  type        = number
  default     = 620
}

variable "replication_public_ip_name" {
  description = "Name of the public IP address on the replication appliance."
  type        = string
  default     = "pip-repl"
}

variable "replication_network_interface_name" {
  description = "Name of the network interface. It joins the public address to the subnet."
  type        = string
  default     = "nic-repl"
}

variable "source_replication_cidr" {
  description = "Public address of the AWS source, with a /32 prefix. Leave this empty until that address exists. A later plan adds the replication rules. The address is not saved in this folder."
  type        = string
  default     = ""

  validation {
    condition     = var.source_replication_cidr == "" || can(cidrhost(var.source_replication_cidr, 0))
    error_message = "Use the source public address with a /32 prefix, or leave it empty."
  }
}

variable "discovery_resource_group_name" {
  description = "Staging resource group from azure/ that holds the discovery virtual machine. Variant B deallocates that machine before creating vm-repl so both Standard_D8as_v4 appliances are not allocated at once."
  type        = string
  default     = "rg-migrate-src-zeon01"
}

variable "discovery_virtual_machine_name" {
  description = "Discovery virtual machine name from azure/. Apply in this folder runs az vm deallocate on it first. That is not terraform destroy: disks and the Migrate project stay."
  type        = string
  default     = "vm-appl-zeon"
}

variable "tags" {
  description = "Base tags. lifetime and created are added in tags.tf. project is the repository folder name."
  type        = map(string)
  default = {
    project     = "06-aws-to-azure-migrate-poc"
    environment = "poc"
    managed-by  = "terraform"
    owner       = "zeon"
  }
}
