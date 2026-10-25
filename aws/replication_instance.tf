# The replication appliance.
# The source instance already looks up the Windows Server 2022 image,
# so this file reuses that lookup. The subnet, replication firewall, and
# key pair are named here. user_data is the appliance guest script, which
# only sets the Windows computer name.
#
# The cache disk is its own volume, then an attachment. Putting it inside
# the instance would make any disk change replace the whole machine.
# The appliance configuration, later, selects this disk. The guest script
# does not format it.
#
# get_password_data waits for the built-in Administrator password, the
# same way the source server does. Remote Desktop uses that password.

resource "aws_instance" "replication" {
  ami                    = data.aws_ami.windows_2022.id
  instance_type          = var.replication_instance_type
  subnet_id              = aws_subnet.subnet.id
  vpc_security_group_ids = [aws_security_group.replication.id]
  key_name               = aws_key_pair.migrate.key_name
  get_password_data      = true

  root_block_device {
    volume_type = "gp3"
    volume_size = var.replication_os_volume_size_gb
    encrypted   = false
  }

  user_data = "<powershell>\n${templatefile("${path.module}/guest/replication-setup.ps1", {
    computer_name = var.replication_computer_name
  })}\n</powershell>\n"

  tags = merge(var.tags, {
    Name = var.replication_instance_name
  })
}

resource "aws_ebs_volume" "replication_cache" {
  availability_zone = aws_subnet.subnet.availability_zone
  size              = var.replication_cache_volume_size_gb
  type              = "gp3"
  encrypted         = false

  tags = merge(var.tags, {
    Name = var.replication_cache_volume_name
  })
}

resource "aws_volume_attachment" "replication_cache" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.replication_cache.id
  instance_id = aws_instance.replication.id
}
