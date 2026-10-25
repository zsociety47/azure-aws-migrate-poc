# The group the migrated server lands in.
# The virtual network and the firewall belong here too, so the next
# files can point at this group. This group does not depend on the
# staging group. Terraform can create the two groups in either order.

resource "azurerm_resource_group" "target" {
  name     = var.target_resource_group_name
  location = var.location
  tags     = var.tags
}
