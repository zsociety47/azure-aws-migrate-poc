# The public address for the discovery appliance.
# Referencing the staging group makes Terraform wait until that group
# exists. The network interface attaches this address.
# The virtual machine in this group uses the subnet in the target group.
#
# This address is the way out. The firewall allows TCP 443 and TCP 5985,
# and this address carries that traffic. Basic addresses are retired.
# Standard addresses are static, so the source firewall can allow this
# one address later.
#
# No Domain Name System (DNS) label. The address does not need a name
# on the internet.

resource "azurerm_public_ip" "discovery" {
  name                = var.discovery_public_ip_name
  resource_group_name = azurerm_resource_group.staging.name
  location            = azurerm_resource_group.staging.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = local.tags

  lifecycle {
    ignore_changes = [tags["created"]]
  }
}
