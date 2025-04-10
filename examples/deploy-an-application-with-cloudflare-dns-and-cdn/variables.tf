```
variable "qovery_organization_id" {
  type    = string
}

variable "qovery_access_token" {
  type = string
}

variable "aws_access_key_id" {
  type = string
}

variable "aws_secret_access_key" {
  type = string
}

variable "cloudflare_email" {
  type = string
}

variable "cloudflare_api_token" {
  type = string
}

variable "cloudflare_zone_id" {
  type = string
}

variable "cloudflare_record_name" {
  type = string
  default = "new-foobar" # Updated
}

variable "qovery_custom_domain" {
  type = string
  default = "new-foobar.meta.cloud" # Updated
}
```