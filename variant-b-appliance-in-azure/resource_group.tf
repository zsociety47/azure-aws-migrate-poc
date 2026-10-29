# The resource group for the replication appliance.
# Deleting this group is the teardown. It is tagged lifetime=1d
# because the virtual machine inside it bills by the hour.

resource "azurerm_resource_group" "replication" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags

  lifecycle {
    ignore_changes = [tags["created"]]
  }
}
