# The public Internet Protocol version 4 (IPv4) address of the machine
# running Terraform. The source firewall allows Remote Desktop only from
# this address. The value is read when Terraform plans, then stored in
# local state. It is not written in this file.
#
# The lookup uses the same service as the other projects, api.ipify.org.
# The Hypertext Transfer Protocol (HTTP) provider is pinned in versions.tf.

data "http" "operator_ip" {
  url = "https://api.ipify.org"

  lifecycle {
    postcondition {
      condition     = can(cidrnetmask("${chomp(self.response_body)}/32"))
      error_message = "The public address lookup did not return an IPv4 address. Check the network connection and run again."
    }
  }
}

locals {
  operator_ip   = chomp(data.http.operator_ip.response_body)
  operator_cidr = "${local.operator_ip}/32"
}
