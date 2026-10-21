# Signs in to Amazon Web Services (AWS) before any resource file runs.
# Later resource files use this provider. They do not sign in themselves.
#
# Authentication uses the AWS command-line interface (CLI) credentials
# already on this machine. The access key stays in the CLI configuration,
# outside this repository.
#
# The CLI has no default region. The region is set here so every resource
# in this folder is created in us-east-1, the region fixed for this build.

provider "aws" {
  region = "us-east-1"
}
