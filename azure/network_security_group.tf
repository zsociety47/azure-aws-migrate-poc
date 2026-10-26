# The firewall for the subnet.
# Referencing the target resource group makes Terraform wait until
# that group exists. This block does not attach the firewall to the
# subnet. The subnet file does that.
#
# Remote Desktop is allowed from the operator address only. Azure adds
# its own rules that allow outbound traffic to the internet and to the
# virtual network, so the discovery appliance can reach the source
# server without a rule in this file.
#
# The address is read when Terraform plans. It is not written here.

data "http" "operator_ip" {
  url = "https://api.ipify.org"

  lifecycle {
    postcondition {
      condition     = can(cidrnetmask("${chomp(self.response_body)}/32"))
      error_message = "The public address lookup did not return an IPv4 address. Check the network connection and run again."
    }
  }
}

locals {
  operator_ip   = chomp(data.http.operator_ip.response_body)
  operator_cidr = "${local.operator_ip}/32"
}

resource "azurerm_network_security_group" "nsg" {
  name                = var.network_security_group_name
  location            = azurerm_resource_group.target.location
  resource_group_name = azurerm_resource_group.target.name

  security_rule {
    name                       = "RemoteDesktopFromOperator"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = local.operator_cidr
    destination_address_prefix = "*"
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [tags["created"]]
  }
}
