# Attaches the firewall to the subnet.
# Both sides already exist. This block is the link between them.
# Remote Desktop from the operator address applies to the subnet only
# after this association exists.

resource "azurerm_subnet_network_security_group_association" "subnet" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}
