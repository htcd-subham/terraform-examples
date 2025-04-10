```
terraform {
  required_providers {
    qovery = {
      source = "qovery/qovery"
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
  name            = "Lifecycle-job"
}

resource "qovery_environment" "production" {
  project_id = qovery_project.my_project.id
  name       = "production"
  mode       = "PRODUCTION"
  cluster_id = qovery_cluster.my_cluster.id
}

# create and deploy lifecycle job triggered on start and on stop
resource "qovery_job" "lifecycle-job-on-start-on-stop" {
  environment_id = qovery_environment.production.id
  name           = "lifecycle-job-on-start-on-stop"

  cpu    = 100
  memory = 350

  max_duration_seconds = 60
  max_nb_restart       = 1

  port = 4000

  auto_preview = false

  schedule = {
    on_start = {
      entrypoint = ""
      arguments = []
    }
    on_stop = {
      entrypoint = ""
      arguments = []
    }
  }

  source = {
    docker = {
      dockerfile_path = "Dockerfile"
      git_repository = {
        url       = "https://github.com/Qovery/terraform-provider-testing.git"
        branch    = "job-echo-n-seconds"
        root_path = "/"
      }
    }
  }

  environment_variables = [
    {
      key   = "PORT"
      value = "4000"
    },
    {
      key   = "DURATION_SECONDS"
      value = "15"
    },
  ]

  secrets = [
    {
      key   = "JOB_SECRET"
      value = "my job secret"
    },
  ]
  healthchecks = {}
}

# create and deploy lifecycle job on delete
resource "qovery_job" "lifecycle-job-on-delete" {
  environment_id = qovery_environment.production.id
  name           = "lifecycle-job-on-delete"

  cpu    = 100
  memory = 350

  max_duration_seconds = 60
  max_nb_restart       = 1

  port = 4000

  auto_preview = false

  schedule = {
    on_delete = {
      entrypoint = ""
      arguments = []
    }
  }

  source = {
    docker = {
      dockerfile_path = "Dockerfile"
      git_repository = {
        url       = "https://github.com/Qovery/terraform-provider-testing.git"
        branch    = "job-echo-n-seconds"
        root_path = "/"
      }
    }
  }

  environment_variables = [
    {
      key   = "PORT"
      value = "4000"
    },
    {
      key   = "DURATION_SECONDS"
      value = "15"
    },
  ]

  secrets = [
    {
      key   = "JOB_SECRET"
      value = "my job secret"
    },
  ]

  healthchecks = {}
}

resource "qovery_deployment" "prod_deployment" {
  environment_id = qovery_environment.production.id
  desired_state  = "RUNNING"
}
```