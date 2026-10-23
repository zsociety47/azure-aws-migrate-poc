# The firewall for the source server.
# Referencing the virtual private cloud (VPC) makes Terraform wait until
# that network exists. This block does not attach the firewall to the
# server. The instance file does that.
#
# Remote Desktop is allowed from the operator address only. The Windows
# Remote Management rule is added when the discovery appliance in Azure
# has a public address.
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
