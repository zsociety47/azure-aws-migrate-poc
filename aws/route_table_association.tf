# Attaches the route table to the subnet.
# Both sides already exist. This block is the link between them.
# An instance in the subnet uses the internet route only after this
# association exists.

resource "aws_route_table_association" "subnet" {
  subnet_id      = aws_subnet.subnet.id
  route_table_id = aws_route_table.route_table.id
}
