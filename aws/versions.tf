# Pins the tool versions before any Amazon Web Services (AWS) resource is declared.
# terraform init reads this block and downloads the providers it names.
# Later resource files depend on those providers staying the same version.
#
# The HTTP provider reads this machine's public address. It creates nothing in AWS.

terraform {
  required_version = "~> 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.69.1"
    }
    http = {
      source  = "hashicorp/http"
      version = "= 3.6.3"
    }
  }
}
