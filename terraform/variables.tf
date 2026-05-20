variable "aws_region" {
  default = "eu-north-1"
}

variable "key_pair_name" {
  description = "Your EC2 key pair name (without .pem)"
  type        = string
}

variable "ami_id" {
  # Ubuntu 22.04 LTS in eu-north-1. If your region is different, update this.
  default = "ami-0c7217cdde317cfec"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "project_name" {
  default = "iii-devops"
}
