# A slice of the virtual network.
# Referencing the virtual network makes Terraform wait until that
# network exists. 10.6.1.0/24 fits inside 10.6.0.0/16.
#
# This resource has no firewall argument. The next file is the
# association that joins nsg-migrate-tgt-zeon to this subnet.

resource "azurerm_subnet" "subnet" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.target.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.subnet_cidr]
}
