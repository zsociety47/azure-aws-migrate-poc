# The rule for traffic that leaves the virtual private cloud (VPC).
# Referencing the VPC and the internet gateway makes Terraform wait
# until both exist.
#
# AWS adds a local route for 10.0.0.0/16 on its own, so the source
# server and the replication appliance can reach each other.
# The route below sends every other address through the gateway.
# This file does not attach the table to the subnet. The association
# file does that.

resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(var.tags, {
    Name = var.route_table_name
  })
}
