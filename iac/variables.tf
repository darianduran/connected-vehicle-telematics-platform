variable "app" {
  description = "The name of the app that prefixes each resource (fleet)"
  type        = string
}

variable "env" {
  description = "Deployment environment (dev/prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod"
  }
}

variable "aws_region" {
  description = "Primary AWS region (Either us-east-1 or us-west-2)"
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "DynamoDB Global Tables DR region"
  type        = string
  default     = "us-west-2"
}

variable "domain_name" {
  description = "FQDN for CloudFront/Route53 (fleet.example.com)"
  type        = string
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone ID for the domain."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Must be valid CIDR notation."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection on resources (dev = false / prod = true)"
  type        = bool
  default     = true
}

variable "cost_center" {
  description = "Cost center tag applied to every resource via provider default_tags."
  type        = string
  default     = "Engineering"
}

variable "owner" {
  description = "Owner tag applied to every resource."
  type        = string
  default     = "platform-team"
}

variable "enable_signed_urls" {
  description = "Enable CloudFront signed URLs for S3 media (dashcam)"
  type        = bool
  default     = false
}

variable "cloudfront_key_pair_id" {
  description = "CloudFront key pair ID associated with the trusted public key. Required when enable_signed_urls is true."
  type        = string
  default     = ""
}

variable "cloudfront_public_key_pem" {
  description = "RSA-2048 public key PEM registered with CloudFront as a trusted signer. Required when enable_signed_urls is true."
  type        = string
  default     = ""
  sensitive   = true
}

variable "cloudfront_private_key_secret_arn" {
  description = "Secrets Manager ARN holding the matching private key used by the token generator Lambda."
  type        = string
  default     = ""
  sensitive   = true
}

variable "image_tag_consumer" {
  description = "ECR image tag for the Telemetry Consumer Service. Used only when deploy_ecs_services is true."
  type        = string
  default     = "latest"
}

variable "image_tag_sse_server" {
  description = "ECR image tag for the SSE Streaming Service. Used only when deploy_ecs_services is true."
  type        = string
  default     = "latest"
}

variable "enable_global_tables" {
  description = "Replicate all DynamoDB tables to dr_region as global tables."
  type        = bool
  default     = false
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway (dev only)"
  type        = bool
  default     = false
}

variable "enable_valkey_multi_az" {
  description = "Enable Valkey multi-AZ with automatic failover (prod only)"
  type        = bool
  default     = false
}

variable "deploy_ecs_services" {
  description = "Deploy ECS services on apply."
  type        = bool
  default     = false ## Keep on false during initial run then switch to true
}

variable "vin_mapping_admin_principal_arns" {
  description = "IAM principal ARNs (users/roles/SAML groups) allowed to assume the vin-mapping admin reader role"
  type        = list(string)
  default     = []
}

variable "manage_scps" {
  description = "Provision SCPs for the organizations."
  type        = bool
  default     = false
}

variable "scp_target_ids" {
  description = "Org root/OU/account IDs to attach SCPs to"
  type        = list(string)
  default     = []
}

variable "enable_s3_crr" {
  description = "Enable S3 cross-region replication for sensitive buckets"
  type        = bool
  default     = null
}
