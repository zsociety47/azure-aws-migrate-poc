# A slice of the virtual private cloud (VPC).
# Referencing the VPC makes Terraform wait until that network exists.
# This block does not mention the internet gateway. The route table
# connects the subnet to the gateway later.
#
# map_public_ip_on_launch gives every instance in this subnet a public
# address. Remote Desktop uses that address, and the discovery appliance
# in Azure reaches the source server on it.

resource "aws_subnet" "subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = var.subnet_name
  })
}
