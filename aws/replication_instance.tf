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
#
# The appliance is 8 virtual CPUs and the source is 2. Both have to be
# running, so the Running On-Demand Standard quota L-1216C47A in
# us-east-1 has to be at least 10. A new account is often still at 8.
# Request 10 before setting replication_instance_enabled to true. A
# larger jump is more likely to wait on a person. If a higher request
# is already open, leave it. count leaves the appliance and the cache
# disk out until that variable is true.
#
# This machine stays in the source virtual private cloud. Azure Migrate
# requires 8 cores, 16 GB of memory, and a cache disk of at least 600 GB
# here, beside the source. The process server on this instance receives
# disk blocks on TCP 9443, compresses them, and uploads them to Azure.
# A smaller instance fails that check. An appliance in Azure is on the
# wrong side of the copy.

resource "aws_instance" "replication" {
  count                  = var.replication_instance_enabled ? 1 : 0
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
  count             = var.replication_instance_enabled ? 1 : 0
  availability_zone = aws_subnet.subnet.availability_zone
  size              = var.replication_cache_volume_size_gb
  type              = "gp3"
  encrypted         = false

  tags = merge(var.tags, {
    Name = var.replication_cache_volume_name
  })
}

resource "aws_volume_attachment" "replication_cache" {
  count       = var.replication_instance_enabled ? 1 : 0
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.replication_cache[count.index].id
  instance_id = aws_instance.replication[count.index].id
}
