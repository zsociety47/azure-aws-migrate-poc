# Signs in to Azure before any resource file in this folder runs.
# Later files use this provider. They do not sign in themselves.
#
# Authentication uses the Azure command-line interface (CLI) login already
# on this machine. The subscription id is read from the ARM_SUBSCRIPTION_ID
# environment variable, so it is not stored in this file.
#
# This folder does not read aws/ or azure/ state. Apply it only while
# vm-appl-zeon is deallocated or absent. Both machines are 8 virtual
# central processing units, and East US allows 10 in total.

provider "azurerm" {
  resource_provider_registrations = "none"

  resource_providers_to_register = [
    "Microsoft.Network",
    "Microsoft.Compute",
  ]

  features {}
}
