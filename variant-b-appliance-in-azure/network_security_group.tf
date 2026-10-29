# The firewall for the replication appliance subnet.
# Remote Desktop is allowed from the operator address only.
# Rules that name the AWS source are added only after
# source_replication_cidr is set. Which of those rules the
# copy actually uses is not verified. See FINDINGS.md.
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

resource "azurerm_network_security_group" "replication" {
  name                = var.network_security_group_name
  location            = azurerm_resource_group.replication.location
  resource_group_name = azurerm_resource_group.replication.name

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

  dynamic "security_rule" {
    for_each = var.source_replication_cidr == "" ? [] : [var.source_replication_cidr]
    content {
      name                       = "ReplicationHttpsFromSource"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = security_rule.value
      destination_address_prefix = "*"
    }
  }

  dynamic "security_rule" {
    for_each = var.source_replication_cidr == "" ? [] : [var.source_replication_cidr]
    content {
      name                       = "ReplicationDataFromSource"
      priority                   = 120
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "9443"
      source_address_prefix      = security_rule.value
      destination_address_prefix = "*"
    }
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
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = var.subnet_cidr
    destination_address_prefix = "AzureCloud"
  }

  dynamic "security_rule" {
    for_each = var.source_replication_cidr == "" ? [] : [var.source_replication_cidr]
    content {
      name                       = "WinRmToSource"
      priority                   = 120
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "5985"
      source_address_prefix      = var.subnet_cidr
      destination_address_prefix = security_rule.value
    }
  }

  dynamic "security_rule" {
    for_each = var.source_replication_cidr == "" ? [] : [var.source_replication_cidr]
    content {
      name                       = "SmbToSource"
      priority                   = 130
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "445"
      source_address_prefix      = var.subnet_cidr
      destination_address_prefix = security_rule.value
    }
  }

  dynamic "security_rule" {
    for_each = var.source_replication_cidr == "" ? [] : [var.source_replication_cidr]
    content {
      name                       = "RpcToSource"
      priority                   = 140
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "135"
      source_address_prefix      = var.subnet_cidr
      destination_address_prefix = security_rule.value
    }
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [tags["created"]]
  }
}
