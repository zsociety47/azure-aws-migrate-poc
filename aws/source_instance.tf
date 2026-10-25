# The Windows server that will be migrated.
# The subnet, firewall, and key pair already exist as code, so this
# instance can name them. The image lookup is here because this is the
# first machine that needs it. The replication appliance reuses the same
# image later.
#
# user_data is the guest script, wrapped for EC2Launch. templatefile
# fills the computer name, discovery username, and discovery password
# before the machine is created. The password is sensitive, so the plan
# hides this block. Windows runs the script once, on first boot.
#
# get_password_data waits until Amazon Web Services (AWS) has encrypted
# the built-in Administrator password with the key pair. The private key
# decrypts it later. That password is not in the guest script.

data "aws_ami" "windows_2022" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_instance" "source" {
  ami                    = data.aws_ami.windows_2022.id
  instance_type          = var.source_instance_type
  subnet_id              = aws_subnet.subnet.id
  vpc_security_group_ids = [aws_security_group.source.id]
  key_name               = aws_key_pair.migrate.key_name
  get_password_data      = true

  root_block_device {
    volume_type = "gp3"
    volume_size = var.source_volume_size_gb
    encrypted   = false
  }

  user_data = "<powershell>\n${templatefile("${path.module}/guest/source-setup.ps1", {
    computer_name      = var.source_computer_name
    discovery_username = var.discovery_username
    discovery_password = var.discovery_password
  })}\n</powershell>\n"

  tags = merge(var.tags, {
    Name = var.source_instance_name
  })
}
