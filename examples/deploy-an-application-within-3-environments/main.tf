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

resource "qovery_aws_credentials" "my_aws_creds" {
  organization_id   = var.qovery_organization_id
  name              = "My AWS Creds"
  access_key_id     = var.aws_access_key_id
  secret_access_key = var.aws_secret_access_key
}

resource "qovery_cluster" "production_cluster" {
  organization_id   = var.qovery_organization_id
  credentials_id    = qovery_aws_credentials.my_aws_creds.id
  name              = "Production cluster"
  description       = "Terraform prod demo cluster"
  cloud_provider    = "AWS"
  region            = "us-east-2"
  instance_type     = "t3a.medium"
  min_running_nodes = 3
  max_running_nodes = 4
}

resource "qovery_cluster" "staging_cluster" {
  organization_id   = var.qovery_organization_id
  credentials_id    = qovery_aws_credentials.my_aws_creds.id
  name              = "Staging cluster"
  description       = "Terraform staging demo cluster"
  cloud_provider    = "AWS"
  region            = "us-east-2"
  instance_type     = "t3a.medium"
  min_running_nodes = 3
  max_running_nodes = 4
}

resource "qovery_cluster" "dev_cluster" {
  organization_id   = var.qovery_organization_id
  credentials_id    = qovery_aws_credentials.my_aws_creds.id
  name              = "Dev cluster"
  description       = "Terraform dev demo cluster"
  cloud_provider    = "AWS"
  region            = "us-east-2"
  instance_type     = "t3a.medium"
  min_running_nodes = 3
  max_running_nodes = 4
}


resource "qovery_project" "my_project" {
  organization_id = var.qovery_organization_id
  name            = "Multi-env Project"
}

resource "qovery_environment" "production" {
  project_id = qovery_project.my_project.id
  name       = "production"
  mode       = "PRODUCTION"
  cluster_id = qovery_cluster.production_cluster.id
}

resource "qovery_database" "production_psql_database" {
  environment_id = qovery_environment.production.id
  name           = "strapi db"
  type           = "POSTGRESQL"
  version        = "13"
  mode           = "MANAGED" # Use AWS RDS for PostgreSQL (backup and PITR automatically configured by Qovery)
  storage        = 10 # 10GB of storage
  accessibility  = "PRIVATE" # do not make it publicly accessible
}

resource "qovery_application" "production_strapi_app" {
  environment_id = qovery_environment.production.id
  name           = "strapi app"
  cpu            = 1000
  memory         = 512
  git_repository = {
    url       = "https://github.com/evoxmusic/strapi-v4.git"
    branch    = "main"
    root_path = "/"
  }
  build_mode            = "DOCKER"
  dockerfile_path       = "Dockerfile"
  min_running_instances = 1
  max_running_instances = 1
  ports                 = [
    {
      internal_port       = 1337
      external_port       = 443
      protocol            = "HTTP"
      publicly_accessible = true
      is_default          = true
    }
  ]
  healthchecks = {
    readiness_probe = {
      type = {
        http = {
          port = 1337
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
          port = 1337
        }
      }
      initial_delay_seconds = 30
      period_seconds        = 10
      timeout_seconds       = 10
      success_threshold     = 1
      failure_threshold     = 3
    }
  }
  environment_variables = [
    {
      key   = "PORT"
      value = "1337"
    },
    {
      key   = "HOST"
      value = "0.0.0.0"
    },
    {
      key   = "DATABASE_HOST"
      value = qovery_database.production_psql_database.internal_host
    },
    {
      key   = "DATABASE_PORT"
      value = qovery_database.production_psql_database.port
    },
    {
      key   = "DATABASE_USERNAME"
      value = qovery_database.production_psql_database.login
    },
    {
      key   = "DATABASE_NAME"
      value = "postgres"
    },
  ]
  secrets = [
    {
      key   = "ADMIN_JWT_SECRET"
      value = var.strapi_admin_jwt_secret
    },
    {
      key   = "API_TOKEN_SALT"
      value = var.strapi_api_token_salt
    },
    {
      key   = "APP_KEYS"
      value = var.strapi_app_keys
    },
    {
      key   = "DATABASE_PASSWORD"
      value = qovery_database.production_psql_database.password
    }
  ]
}

resource "qovery_deployment" "prod_deployment" {
  environment_id = qovery_environment.production.id
  desired_state  = "RUNNING"
}

resource "qovery_environment" "staging" {
  project_id = qovery_project.my_project.id
  name       = "staging"
  mode       = "STAGING"
  cluster_id = qovery_cluster.staging_cluster.id
}

resource "qovery_database" "staging_psql_database" {
  environment_id = qovery_environment.staging.id
  name           = "strapi db"
  type           = "POSTGRESQL"
  version        = "13"
  mode           = "MANAGED" # Use AWS RDS for PostgreSQL (backup and PITR automatically configured by Qovery)
  storage        = 10 # 10GB of storage
  accessibility  = "PRIVATE" # do not make it publicly accessible
}

resource "qovery_application" "staging_strapi_app" {
  environment_id = qovery_environment.staging.id
  name           = "strapi app"
  cpu            = 1000
  memory         = 512
  git_repository = {
    url       = "https://github.com/evoxmusic/strapi-v4.git"
    branch    = "main"
    root_path = "/"
  }
  build_mode            = "DOCKER"
  dockerfile_path       = "Dockerfile"
  min_running_instances = 1
  max_running_instances = 1
  ports                 = [
    {
      internal_port       = 1337
      external_port       = 443
      protocol            = "HTTP"
      publicly_accessible = true
      is_default          = true
    }
  ]
  healthchecks = {
    readiness_probe = {
      type = {
        http = {
          port = 1337
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
          port = 1337
        }
      }
      initial_delay_seconds = 30
      period_seconds        = 10
      timeout_seconds       = 10
      success_threshold     = 1
      failure_threshold     = 3
    }
  }
  environment_variables = [
    {
      key   = "PORT"
      value = "1337"
    },
    {
      key   = "HOST"
      value = "0.0.0.0"
    },
    {
      key   = "DATABASE_HOST"
      value = qovery_database.staging_psql_database.internal_host
    },
    {
      key   = "DATABASE_PORT"
      value = qovery_database.staging_psql_database.port
    },
    {
      key   = "DATABASE_USERNAME"
      value = qovery_database.staging_psql_database.login
    },
    {
      key   = "DATABASE_NAME"
      value = "postgres"
    },
  ]
  secrets = [
    {
      key   = "ADMIN_JWT_SECRET"
      value = var.strapi_admin_jwt_secret
    },
    {
      key   = "API_TOKEN_SALT"
      value = var.strapi_api_token_salt
    },
    {
      key   = "APP_KEYS"
      value = var.strapi_app_keys
    },
    {
      key   = "DATABASE_PASSWORD"
      value = qovery_database.staging_psql_database.password
    }
  ]
}

resource "qovery_deployment" "staging_deployment" {
  environment_id = qovery_environment.staging.id
  desired_state  = "RUNNING"
}

resource "qovery_environment" "dev" {
  project_id = qovery_project.my_project.id
  name       = "dev"
  mode       = "DEVELOPMENT"
  cluster_id = qovery_cluster.dev_cluster.id
}

resource "qovery_database" "dev_psql_database" {
  environment_id = qovery_environment.dev.id
  name           = "strapi db"
  type           = "POSTGRESQL"
  version        = "13"
  mode           = "CONTAINER" # Use a container for development purpose
  storage        = 10 # 10GB of storage
  accessibility  = "PRIVATE" # do not make it publicly accessible
}

resource "qovery_application" "dev_strapi_app" {
  environment_id = qovery_environment.staging.id
  name           = "strapi app"
  cpu            = 1000
  memory         = 512
  git_repository = {
    url       = "https://github.com/evoxmusic/strapi-v4.git"
    branch    = "main"
    root_path = "/"
  }
  build_mode            = "DOCKER"
  dockerfile_path       = "Dockerfile"
  min_running_instances = 1
  max_running_instances = 1
  ports                 = [
    {
      internal_port       = 1337
      external_port       = 443
      protocol            = "HTTP"
      publicly_accessible = true
      is_default          = true
    }
  ]
  healthchecks = {
    readiness_probe = {
      type = {
        http = {
          port = 1337
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
          port = 1337
        }
      }
      initial_delay_seconds = 30
      period_seconds        = 10
      timeout_seconds       = 10
      success_threshold     = 1
      failure_threshold     = 3
    }
  }
  environment_variables = [
    {
      key   = "PORT"
      value = "1337"
    },
    {
      key   = "HOST"
      value = "0.0.0.0"
    },
    {
      key   = "DATABASE_HOST"
      value = qovery_database.dev_psql_database.internal_host
    },
    {
      key   = "DATABASE_PORT"
      value = qovery_database.dev_psql_database.port
    },
    {
      key   = "DATABASE_USERNAME"
      value = qovery_database.dev_psql_database.login
    },
    {
      key   = "DATABASE_NAME"
      value = "postgres"
    },
  ]
  secrets = [
    {
      key   = "ADMIN_JWT_SECRET"
      value = var.strapi_admin_jwt_secret
    },
    {
      key   = "API_TOKEN_SALT"
      value = var.strapi_api_token_salt
    },
    {
      key   = "APP_KEYS"
      value = var.strapi_app_keys
    },
    {
      key   = "DATABASE_PASSWORD"
      value = qovery_database.dev_psql_database.password
    }
  ]
}

resource "qovery_deployment" "dev_deployment" {
  environment_id = qovery_environment.dev.id
  desired_state  = "RUNNING"
}```