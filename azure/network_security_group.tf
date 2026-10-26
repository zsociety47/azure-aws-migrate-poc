# The firewall for the subnet.
# Referencing the target resource group makes Terraform wait until
# that group exists. This block does not attach the firewall to the
# subnet. nsg_association.tf does that.
#
# Remote Desktop is allowed from the operator address only.
# Outbound is pinned to the two things the discovery appliance does:
# Hypertext Transfer Protocol Secure (HTTPS) on TCP 443 toward Azure
# and the public internet, and Windows Remote Management (WinRM) on
# TCP 5985 toward the source server's public address. Each service
# tag is its own rule. Azure rejects two tags in one rule. The public
# address on the discovery virtual machine carries that traffic.
#
# The operator address is read when Terraform plans. It is not written here.

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

  security_rule {
    name                       = "HttpsToInternet"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = var.subnet_cidr
    destination_address_prefix = "Internet"
  }

  security_rule {
    name                       = "HttpsToAzure"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = var.subnet_cidr
    destination_address_prefix = "AzureCloud"
  }

  security_rule {
    name                       = "WinRmOutboundToSource"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5985"
    source_address_prefix      = var.subnet_cidr
    destination_address_prefix = "Internet"
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [tags["created"]]
  }
}
