# Signs in to Azure before any resource file runs.
# Later resource files use this provider. They do not sign in themselves.
#
# Authentication uses the Azure command-line interface (CLI) login already
# on this machine. The subscription id is read from the ARM_SUBSCRIPTION_ID
# environment variable, so it is not stored in this file. ARM is the prefix
# the Azure Resource Manager provider uses for its environment variables.
#
# Each resource carries its own location. East US is set in the variables
# file, which is where the locked names live.
#
# Version 5 of this provider registers no resource providers unless the
# file asks for them. Microsoft.Network is the virtual network and the
# firewall. Microsoft.Compute is the discovery appliance, later.

provider "azurerm" {
  resource_provider_registrations = "none"

  resource_providers_to_register = [
    "Microsoft.Network",
    "Microsoft.Compute",
  ]

  features {}
}
