# The network interface joins the public address to the subnet.
# The virtual machine attaches this interface.

resource "azurerm_network_interface" "replication" {
  name                = var.replication_network_interface_name
  location            = azurerm_resource_group.replication.location
  resource_group_name = azurerm_resource_group.replication.name

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.replication.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.replication.id
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [tags["created"]]
  }
}
