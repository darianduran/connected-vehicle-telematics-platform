provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.app
      Environment = var.env
      ManagedBy   = "Terraform"
    }
  }
}
