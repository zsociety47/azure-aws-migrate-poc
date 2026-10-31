# The firewall for the source server.
# Referencing the virtual private cloud (VPC) makes Terraform wait until
# that network exists. This block does not attach the firewall to the
# server. The instance file does that.
#
# Remote Desktop is allowed from the operator address only. The
# replication appliance installs the Mobility service from this subnet,
# so ports 445, 135, and 5985 are open to the subnet. Windows Remote
# Management from the discovery appliance is a separate rule, and only
# when discovery_winrm_cidr is set to that appliance's public /32.
# Variant B puts the replication appliance in Azure, so Mobility also
# needs 445, 135, and 5985 from pip-repl when variant_b_mobility_cidr is set.
#
# The egress rule lets the server start connections. Replication sends
# disk changes to the appliance, and Windows uses outbound internet for
# activation and time sync. A security group is stateful, so the reply
# to an allowed inbound connection is allowed without a second rule.

resource "aws_security_group" "source" {
  name        = var.source_security_group_name
  description = "Remote Desktop to the source server from the operator address."
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "Remote Desktop from the operator address"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [local.operator_cidr]
  }

  ingress {
    description = "Mobility file copy from the replication appliance"
    from_port   = 445
    to_port     = 445
    protocol    = "tcp"
    cidr_blocks = [var.subnet_cidr]
  }

  ingress {
    description = "Mobility remote procedure call from the replication appliance"
    from_port   = 135
    to_port     = 135
    protocol    = "tcp"
    cidr_blocks = [var.subnet_cidr]
  }

  ingress {
    description = "Windows Remote Management from the replication appliance"
    from_port   = 5985
    to_port     = 5985
    protocol    = "tcp"
    cidr_blocks = [var.subnet_cidr]
  }

  dynamic "ingress" {
    for_each = var.discovery_winrm_cidr == "" ? [] : [var.discovery_winrm_cidr]
    content {
      description = "Windows Remote Management from the discovery appliance"
      from_port   = 5985
      to_port     = 5985
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  dynamic "ingress" {
    for_each = var.variant_b_mobility_cidr == "" ? [] : [var.variant_b_mobility_cidr]
    content {
      description = "Mobility file copy from the Variant B replication appliance"
      from_port   = 445
      to_port     = 445
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  dynamic "ingress" {
    for_each = var.variant_b_mobility_cidr == "" ? [] : [var.variant_b_mobility_cidr]
    content {
      description = "Mobility remote procedure call from the Variant B replication appliance"
      from_port   = 135
      to_port     = 135
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  dynamic "ingress" {
    for_each = var.variant_b_mobility_cidr == "" ? [] : [var.variant_b_mobility_cidr]
    content {
      description = "Windows Remote Management from the Variant B replication appliance"
      from_port   = 5985
      to_port     = 5985
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    description = "Outbound connections from the source server"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = var.source_security_group_name
  })
}
