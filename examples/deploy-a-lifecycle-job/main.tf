```
resource "qovery_application" "backend" {
  environment_id = qovery_environment.production.id
  name           = "url-shortener-backend"  # More descriptive name
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
      internal_port       = local.app_port
      external_port       = 443
      protocol            = "HTTP"
      publicly_accessible = true
      is_default          = true
    }
  ]
  
  # Use environment variable block for better organization
  environment_variables = [
    {
      key   = "DEBUG"
      value = "false"
    },
    {
      key   = "APP_ENV"
      value = "production"
    }
  ]
  
  # Use the local variable for health checks to avoid repetition
  healthchecks = {
    readiness_probe = local.health_check_config
    liveness_probe  = local.health_check_config
  }
  
  # Add auto-restart policy
  auto_preview = false
  auto_deploy  = true
}
```