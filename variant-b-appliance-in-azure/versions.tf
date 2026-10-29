# Pins the tool versions for this folder only.
# terraform init in this folder downloads these providers.
# The aws/ and azure/ folders keep their own copies and their own state.
#
# azurerm creates the replication appliance and its network.
# The HTTP provider reads this machine's public address for the firewall.
# It creates nothing in Azure.

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
