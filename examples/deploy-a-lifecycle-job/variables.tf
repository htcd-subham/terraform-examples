###
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
  default     = "vpc-0ddd932ce1bd038f6"
}

variable "security_group_id" {
  description = "ID of the security group to be updated"
  type        = string
  default     = "sg-08fe4af16da156c0e"
}

variable "allowed_cidr_blocks" {
  description = "List of allowed CIDR blocks for inbound traffic"
  type        = list(string)
  default     = ["10.0.0.0/16"] # Replace with your actual allowed CIDR blocks
}

resource "aws_security_group_rule" "restrict_inbound" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = var.security_group_id
}

resource "aws_security_group_rule" "restrict_outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = var.security_group_id
}

resource "aws_security_group" "update_existing" {
  name        = "updated-default-sg"
  description = "Updated security group with restricted access"
  vpc_id      = var.vpc_id

  tags = {
    Name = "UpdatedDefaultSecurityGroup"
  }

  # Remove all existing rules
  ingress = []
  egress  = []

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "allow_internal_traffic" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.update_existing.id
  security_group_id        = aws_security_group.update_existing.id
}
###