# The replication appliance.
# Referencing the network interface makes Terraform wait until the
# public address and the subnet exist.
#
# Standard_D8as_v4 is 8 virtual CPUs and 32 GB. The Windows image
# requires a 127 GB operating-system disk. The installer script is
# downloaded from Azure Migrate later. It is not in this file.
#
# The password comes from TF_VAR_replication_admin_password.
# Do not put it in a tfvars file.

resource "azurerm_windows_virtual_machine" "replication" {
  name                  = var.replication_virtual_machine_name
  computer_name         = var.replication_computer_name
  resource_group_name   = azurerm_resource_group.replication.name
  location              = azurerm_resource_group.replication.location
  size                  = var.replication_virtual_machine_size
  admin_username        = var.replication_admin_username
  admin_password        = var.replication_admin_password
  network_interface_ids = [azurerm_network_interface.replication.id]

  os_disk {
    name                 = var.replication_os_disk_name
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 127
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2"
    version   = "latest"
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [tags["created"]]
  }
}
