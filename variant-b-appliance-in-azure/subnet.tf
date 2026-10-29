# The subnet that holds the replication appliance.
# The firewall association is a separate file. This block only
# creates the address range.

resource "azurerm_subnet" "replication" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.replication.name
  virtual_network_name = azurerm_virtual_network.replication.name
  address_prefixes     = [var.subnet_cidr]
}
