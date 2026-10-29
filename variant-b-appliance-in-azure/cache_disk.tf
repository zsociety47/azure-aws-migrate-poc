# The cache disk the installer selects later.
# It is a separate disk so a size change does not rebuild the
# virtual machine. It is left empty. The guest does not format it.
# 620 GB of Standard solid-state drive (SSD) is billed as the
# 1024 GB tier.

resource "azurerm_managed_disk" "cache" {
  name                 = var.replication_cache_disk_name
  location             = azurerm_resource_group.replication.location
  resource_group_name  = azurerm_resource_group.replication.name
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.replication_cache_disk_size_gb
  tags                 = local.tags

  lifecycle {
    ignore_changes = [tags["created"]]
  }
}

resource "azurerm_virtual_machine_data_disk_attachment" "cache" {
  managed_disk_id    = azurerm_managed_disk.cache.id
  virtual_machine_id = azurerm_windows_virtual_machine.replication.id
  lun                = 0
  caching            = "ReadWrite"
}
