###
terraform {
  required_providers {
    qovery = {
      source = "qovery/qovery"
    }
    cloudflare = {
      source = "cloudflare/cloudflare"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "qovery" {
  token = var.qovery_access_token
}

provider "cloudflare" {
  email     = var.cloudflare_email
  api_token = var.cloudflare_api_token
}

provider "aws" {
  region = "us-east-1"
}

resource "qovery_aws_credentials" "my_aws_creds" {
  organization_id   = var.qovery_organization_id
  name              = "My AWS Creds"
  access_key_id     = var.aws_access_key_id
  secret_access_key = var.aws_secret_access_key
}

resource "qovery_cluster" "my_cluster" {
  organization_id   = var.qovery_organization_id
  credentials_id    = qovery_aws_credentials.my_aws_creds.id
  name              = "Demo cluster"
  description       = "Terraform demo cluster"
  cloud_provider    = "AWS"
  region            = "us-east-2"
  instance_type     = "t3a.medium"
  min_running_nodes = 3
  max_running_nodes = 4
}

resource "qovery_project" "my_project" {
  organization_id = var.qovery_organization_id
  name            = "URL Shortener"
}

resource "qovery_environment" "production" {
  project_id = qovery_project.my_project.id
  name       = "production"
  mode       = "PRODUCTION"
  cluster_id = qovery_cluster.my_cluster.id
}

# create and deploy app with custom domain
resource "qovery_application" "backend" {
  environment_id = qovery_environment.production.id
  name           = "backend"
  cpu            = 500
  memory         = 256
  git_repository = {
    url       = "https://github.com/evoxmusic/ShortMe-URL-Shortener.git"
    branch    = "main"
    root_path = "/"
  }
  build_mode            = "DOCKER"
  dockerfile_path       = "Dockerfile"
  min_running_instances = 1
  max_running_instances = 1
  custom_domains = [
    {
      domain = var.qovery_custom_domain
    }
  ]
  ports = [
    {
      internal_port       = 5555
      external_port       = 443
      protocol            = "HTTP"
      publicly_accessible = true
      is_default          = true
    }
  ]
  environment_variables = [
    {
      key   = "DEBUG"
      value = "false"
    }
  ]
  healthchecks = {
    readiness_probe = {
      type = {
        http = {
          scheme = "HTTP"
          port   = 5555
          path   = "/"
        }
      }
      initial_delay_seconds = 30
      period_seconds        = 10
      timeout_seconds       = 10
      success_threshold     = 1
      failure_threshold     = 3
    }
    liveness_probe = {
      type = {
        http = {
          scheme = "HTTP"
          port   = 5555
          path   = "/"
        }
      }
      initial_delay_seconds = 30
      period_seconds        = 10
      timeout_seconds       = 10
      success_threshold     = 1
      failure_threshold     = 3
    }
  }
}

resource "qovery_deployment" "prod_deployment" {
  environment_id = qovery_environment.production.id
  desired_state  = "RUNNING"
}

# create custom domain record
resource "cloudflare_record" "foobar" {
  zone_id = var.cloudflare_zone_id
  name    = var.cloudflare_record_name
  value = one(qovery_application.backend.custom_domains[*].validation_domain)
  type    = "CNAME"
  ttl     = 3600
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
