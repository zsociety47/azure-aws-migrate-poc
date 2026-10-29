# Attaches the firewall to the subnet.
# The subnet and the firewall must both exist first.

resource "azurerm_subnet_network_security_group_association" "replication" {
  subnet_id                 = azurerm_subnet.replication.id
  network_security_group_id = azurerm_network_security_group.replication.id
}
