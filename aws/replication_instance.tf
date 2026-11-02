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
# The appliance must report NumberOfCores >= 8. c5.2xlarge is 8 vCPUs
# and 4 cores; Azure Site Recovery failed that check on 2026-10-31.
# c5.4xlarge with hyperthreading off is 8 cores and 8 vCPUs. Count 8
# against quota L-1216C47A together with the source (2). A default
# c5.4xlarge is 16 vCPUs and does not fit. count leaves the appliance
# and the cache disk out until replication_instance_enabled is true.
#
# This machine stays in the source virtual private cloud. Azure Migrate
# requires 8 cores, 16 GB of memory, and a cache disk of at least 600 GB
# here, beside the source.

resource "aws_instance" "replication" {
  count                  = var.replication_instance_enabled ? 1 : 0
  ami                    = data.aws_ami.windows_2022.id
  instance_type          = var.replication_instance_type
  subnet_id              = aws_subnet.subnet.id
  vpc_security_group_ids = [aws_security_group.replication.id]
  key_name               = aws_key_pair.migrate.key_name
  get_password_data      = true

  cpu_options {
    core_count       = 8
    threads_per_core = 1
  }

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
