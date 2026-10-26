# The network interface for the discovery appliance.
# It joins two things that already exist: the public address in this
# staging group, and the subnet in the target group. Azure allows a
# network interface in one group to use a subnet in another. The virtual
# machine attaches this interface.
#
# The private address comes from 10.6.1.0/24 when the interface is
# created. The firewall is already on the subnet, so this interface does
# not attach that firewall a second time.

resource "azurerm_network_interface" "discovery" {
  name                = var.discovery_network_interface_name
  location            = azurerm_resource_group.staging.location
  resource_group_name = azurerm_resource_group.staging.name

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.discovery.id
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [tags["created"]]
  }
}
