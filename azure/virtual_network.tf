# The network the migrated server and the discovery appliance use.
# Referencing the target resource group makes Terraform wait until
# that group exists. The subnet is a later file. It is cut from the
# address space below.

resource "azurerm_virtual_network" "vnet" {
  name                = var.virtual_network_name
  location            = azurerm_resource_group.target.location
  resource_group_name = azurerm_resource_group.target.name
  address_space       = [var.virtual_network_cidr]
  tags                = var.tags
}
