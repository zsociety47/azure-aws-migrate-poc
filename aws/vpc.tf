# The network that later subnets are cut from.
# The internet gateway, the subnet, and the route table reference this block,
# so Terraform creates the virtual private cloud (VPC) first.
#
# enable_dns_support turns on the Amazon DNS resolver inside the VPC.
# enable_dns_hostnames gives each instance a public hostname to go with
# its public address. Remote Desktop and the appliance's calls to Azure
# use that address.

resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = var.vpc_name
  })
}
