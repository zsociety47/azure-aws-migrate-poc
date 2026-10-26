# The discovery appliance.
# Referencing the network interface makes Terraform wait until the
# public address, the subnet, and the interface exist. The virtual
# machine is recorded in the staging group. The interface places it
# on the subnet in the target group.
#
# Microsoft's physical appliance needs Windows Server 2022, 8 virtual
# CPUs, 32 GB of memory, and about 80 GB of disk. The Windows image
# itself is 127 GB, and Azure refuses a smaller disk. Standard_D8as_v4 is
# that size. The newer 8-by-32 sizes are offered in East US, and this
# subscription's quota for those families is 0. The DASv4 family quota
# is 10, which fits this machine.
#
# The installer script is downloaded from the Azure Migrate project
# later. It is not in this file. The password is read from
# terraform.tfvars, which is gitignored.

resource "azurerm_windows_virtual_machine" "discovery" {
  name                  = var.discovery_virtual_machine_name
  computer_name         = var.discovery_computer_name
  resource_group_name   = azurerm_resource_group.staging.name
  location              = azurerm_resource_group.staging.location
  size                  = var.discovery_virtual_machine_size
  admin_username        = var.discovery_admin_username
  admin_password        = var.discovery_admin_password
  network_interface_ids = [azurerm_network_interface.discovery.id]

  os_disk {
    name                 = var.discovery_os_disk_name
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
