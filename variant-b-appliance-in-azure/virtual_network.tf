# The virtual network for the replication appliance.
# 10.7.0.0/16 stays clear of the AWS source at 10.0.0.0/16
# and of the discovery network at 10.6.0.0/16.

resource "azurerm_virtual_network" "replication" {
  name                = var.virtual_network_name
  location            = azurerm_resource_group.replication.location
  resource_group_name = azurerm_resource_group.replication.name
  address_space       = [var.virtual_network_cidr]
  tags                = local.tags

  lifecycle {
    ignore_changes = [tags["created"]]
  }
}
