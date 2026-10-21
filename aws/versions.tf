# Pins the tool versions before any Amazon Web Services (AWS) resource is declared.
# terraform init reads this block and downloads the provider it names.
# Later resource files depend on that provider staying the same version.

terraform {
  required_version = "~> 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.69.1"
    }
  }
}
