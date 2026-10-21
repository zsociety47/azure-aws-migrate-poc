# Names, addresses, sizes, and tags for the Amazon Web Services (AWS) side.
# The provider is already configured. Resource files read these values
# so a name is written once and reused everywhere.
# The region stays in provider.tf. The availability zone below must stay
# inside us-east-1.

variable "vpc_name" {
  description = "Name of the virtual private cloud (VPC)."
  type        = string
  default     = "vpc-migrate-zeon"
}

variable "vpc_cidr" {
  description = "Address space of the VPC. The subnet prefix must fit inside it."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_name" {
  description = "Name of the subnet that holds the source server and the replication appliance."
  type        = string
  default     = "snet-migrate-zeon"
}

variable "subnet_cidr" {
  description = "Address prefix of the subnet. This is a slice of the VPC address space."
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "Availability zone for the subnet. Must be a zone in us-east-1."
  type        = string
  default     = "us-east-1a"
}

variable "internet_gateway_name" {
  description = "Name of the internet gateway attached to the VPC."
  type        = string
  default     = "igw-migrate-zeon"
}

variable "route_table_name" {
  description = "Name of the route table that sends internet traffic through the gateway."
  type        = string
  default     = "rt-migrate-zeon"
}

variable "source_security_group_name" {
  description = "Name of the firewall on the source server."
  type        = string
  default     = "migrate-src-sg-zeon"
}

variable "replication_security_group_name" {
  description = "Name of the firewall on the replication appliance."
  type        = string
  default     = "migrate-repl-sg-zeon"
}

variable "key_pair_name" {
  description = "Name of the AWS key pair created from the local public key."
  type        = string
  default     = "key-migrate-zeon"
}

variable "source_instance_name" {
  description = "Name of the Windows server that will be migrated."
  type        = string
  default     = "ec2-migrate-src-zeon"
}

variable "source_computer_name" {
  description = "Windows computer name of the source server. 15 characters is the maximum."
  type        = string
  default     = "src-zeon"
}

variable "source_instance_type" {
  description = "EC2 instance type for the source server. t3.medium is 2 vCPU and 4 GB."
  type        = string
  default     = "t3.medium"
}

variable "source_volume_size_gb" {
  description = "Root disk size of the source server, in gibibytes."
  type        = number
  default     = 30
}

variable "replication_instance_name" {
  description = "Name of the replication appliance instance."
  type        = string
  default     = "ec2-migrate-repl-zeon"
}

variable "replication_computer_name" {
  description = "Windows computer name of the replication appliance. 15 characters is the maximum."
  type        = string
  default     = "repl-zeon"
}

variable "replication_instance_type" {
  description = "EC2 instance type for the replication appliance. c5.2xlarge is 8 vCPU and 16 GB."
  type        = string
  default     = "c5.2xlarge"
}

variable "replication_os_volume_size_gb" {
  description = "Operating-system disk size of the replication appliance, in gibibytes."
  type        = number
  default     = 80
}

variable "replication_cache_volume_size_gb" {
  description = "Cache disk size of the replication appliance, in gibibytes. The appliance requires 620."
  type        = number
  default     = 620
}

variable "tags" {
  description = "Tags on every AWS resource in this build."
  type        = map(string)
  default = {
    project     = "azure-aws-migrate-poc"
    environment = "poc"
    managed-by  = "terraform"
    owner       = "zeon"
  }
}
