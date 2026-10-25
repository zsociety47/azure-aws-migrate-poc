# The public half of the local Secure Shell (SSH) key.
# Both Windows instances reference this key. Amazon Web Services (AWS)
# encrypts the Administrator password with the public half. The private
# half stays in keys/ and is how that password is retrieved.
#
# Windows password retrieval accepts an RSA key in PEM form. An ED25519
# key cannot decrypt that password. The private key was created with
# ssh-keygen -t rsa -b 2048 -m PEM. Git ignores keys/.

resource "aws_key_pair" "migrate" {
  key_name   = var.key_pair_name
  public_key = file("${path.module}/../keys/id_rsa.pub")

  tags = merge(var.tags, {
    Name = var.key_pair_name
  })
}
