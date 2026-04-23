variable "prefix" { type = string }

variable "vpc_cidr" {
  type = string
}

variable "aws_region" { type = string }

variable "single_nat_gateway" {
  description = "Use a single NAT gateway (dev cost-saver) instead of one per AZ (prod)."
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
