# The path from this virtual private cloud (VPC) to the internet.
# Referencing the VPC makes Terraform wait until that network exists.
# The route table sends internet traffic through this gateway.
# The gateway has no hourly charge.

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = merge(var.tags, {
    Name = var.internet_gateway_name
  })
}
