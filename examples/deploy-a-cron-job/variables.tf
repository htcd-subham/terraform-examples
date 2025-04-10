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

variable "security_group_id" {
  description = "The ID of the security group to remediate"
  type        = string
  default     = "sg-0a3d5f08adf1c2e5a"
}

variable "allowed_ports" {
  description = "List of allowed ports"
  type        = list(number)
  default     = [80, 443] # Example: Allow only HTTP and HTTPS
}

variable "allowed_cidr_blocks" {
  description = "List of allowed CIDR blocks"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] # Example: Allow only private IP ranges
}

# Data source to fetch existing security group
data "aws_security_group" "target_sg" {
  id = var.security_group_id
}

# Remove all existing ingress rules
resource "aws_security_group_rule" "remove_all_rules" {
  count = length(data.aws_security_group.target_sg.ingress)

  security_group_id = var.security_group_id
  type              = "ingress"
  
  from_port   = data.aws_security_group.target_sg.ingress[count.index].from_port
  to_port     = data.aws_security_group.target_sg.ingress[count.index].to_port
  protocol    = data.aws_security_group.target_sg.ingress[count.index].protocol
  cidr_blocks = data.aws_security_group.target_sg.ingress[count.index].cidr_blocks

  lifecycle {
    create_before_destroy = true
  }
}

# Add new ingress rules for allowed ports and CIDR blocks
resource "aws_security_group_rule" "allow_specific_ports" {
  count = length(var.allowed_ports) * length(var.allowed_cidr_blocks)

  security_group_id = var.security_group_id
  type              = "ingress"
  
  from_port   = var.allowed_ports[floor(count.index / length(var.allowed_cidr_blocks))]
  to_port     = var.allowed_ports[floor(count.index / length(var.allowed_cidr_blocks))]
  protocol    = "tcp"
  cidr_blocks = [var.allowed_cidr_blocks[count.index % length(var.allowed_cidr_blocks)]]

  description = "Allow inbound traffic on port ${var.allowed_ports[floor(count.index / length(var.allowed_cidr_blocks))]} from ${var.allowed_cidr_blocks[count.index % length(var.allowed_cidr_blocks)]}"

  depends_on = [aws_security_group_rule.remove_all_rules]
}

# Update tags for auditing
resource "aws_ec2_tag" "security_group_tag" {
  resource_id = var.security_group_id
  key         = "LastRemediated"
  value       = timestamp()
}
###