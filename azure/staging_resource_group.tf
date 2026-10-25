# The group for the Migrate project and the discovery appliance.
# Nothing else in this folder depends on it yet. The virtual network
# goes in the target group, because that is where the migrated server
# and the firewall belong. A virtual machine in this group can still
# use a subnet from that other group.

resource "azurerm_resource_group" "staging" {
  name     = var.staging_resource_group_name
  location = var.location
  tags     = var.tags
}
