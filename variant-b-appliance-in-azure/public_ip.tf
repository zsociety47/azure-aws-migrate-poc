# The public address on the replication appliance.
# Standard and static. No Domain Name System (DNS) label.
# This address is the path for Remote Desktop and, once the
# source address is set, for replication traffic.

resource "azurerm_public_ip" "replication" {
  name                = var.replication_public_ip_name
  location            = azurerm_resource_group.replication.location
  resource_group_name = azurerm_resource_group.replication.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags

  lifecycle {
    ignore_changes = [tags["created"]]
  }
}
