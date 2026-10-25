# The firewall for the replication appliance.
# Referencing the virtual private cloud (VPC) makes Terraform wait until
# that network exists. This block does not attach the firewall to the
# appliance. The instance file does that.
#
# The source server sends replication control traffic on port 443 and
# disk data on port 9443. Both are limited to the source subnet.
# Remote Desktop is allowed from the operator address only.
#
# Outbound Hypertext Transfer Protocol Secure (HTTPS) carries replication
# data to Azure and registers the appliance. Outbound User Datagram
# Protocol (UDP) port 123 lets the appliance match internet time, which
# registration requires. A security group is stateful, so the reply to an
# allowed inbound connection is allowed without a second rule.

resource "aws_security_group" "replication" {
  name        = var.replication_security_group_name
  description = "Remote Desktop and replication traffic for the appliance."
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "Remote Desktop from the operator address"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [local.operator_cidr]
  }

  ingress {
    description = "Replication control from the source subnet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.subnet_cidr]
  }

  ingress {
    description = "Replication data from the source subnet"
    from_port   = 9443
    to_port     = 9443
    protocol    = "tcp"
    cidr_blocks = [var.subnet_cidr]
  }

  egress {
    description = "HTTPS to Azure"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Time sync"
    from_port   = 123
    to_port     = 123
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = var.replication_security_group_name
  })
}
