# Pins the tool versions before any Azure resource is declared.
# terraform init reads this block and downloads the providers it names.
# Later resource files depend on those providers staying the same version.
#
# azurerm creates the resource groups, the virtual network, and later
# the discovery appliance. This root does not create an app registration,
# so the Azure Active Directory provider is not listed.
# The HTTP provider reads this machine's public address for the firewall
# rules. It creates nothing in Azure.

terraform {
  required_version = "~> 1.15.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 5.11.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "= 3.6.3"
    }
  }
}
