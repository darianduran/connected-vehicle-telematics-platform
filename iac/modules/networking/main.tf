module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.6"

  name = "${var.prefix}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets  = [cidrsubnet(var.vpc_cidr, 8, 1), cidrsubnet(var.vpc_cidr, 8, 3)]
  private_subnets = [cidrsubnet(var.vpc_cidr, 8, 2), cidrsubnet(var.vpc_cidr, 8, 4)]

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_flow_log                                 = true
  flow_log_destination_type                       = "cloud-watch-logs"
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_cloudwatch_log_group_retention_in_days = 90
  flow_log_max_aggregation_interval               = 60

  tags = var.tags
}

data "aws_availability_zones" "available" { state = "available" }

# gateway endpoints - free, private connectivity
# Per §5.2.1, endpoint policies are scoped to platform resources only.
# Platform table/bucket ARNs are passed in by name patterns to avoid a
# hard dependency on the s3/dynamodb modules (which would create a cycle).

data "aws_caller_identity" "current" {}

locals {
  acct_id = data.aws_caller_identity.current.account_id

  # Platform table ARNs (both primary and index). Pattern match via prefix.
  platform_ddb_arn_pattern = "arn:aws:dynamodb:${var.aws_region}:${local.acct_id}:table/${var.prefix}-*"

  # Platform bucket ARNs.
  platform_s3_arn_pattern = "arn:aws:s3:::${var.prefix}-*"

  # vin-mapping is read-only through the endpoint (§5.2.1 table).
  vin_mapping_arn = "arn:aws:dynamodb:${var.aws_region}:${local.acct_id}:table/${var.prefix}-vin-mapping"
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PlatformBucketsOnly"
      Effect    = "Allow"
      Principal = "*"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:AbortMultipartUpload",
        "s3:ListBucketMultipartUploads",
      ]
      Resource = [
        local.platform_s3_arn_pattern,
        "${local.platform_s3_arn_pattern}/*",
      ]
    }]
  })

  tags = merge(var.tags, { Name = "${var.prefix}-s3-gw" })
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids

  # Two statements: full CRUD on operational tables, read-only on vin-mapping
  # (§5.2.1 - isolated, admin-restricted via separate IAM).
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PlatformTablesCRUD"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:BatchGetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:DescribeTable",
          "dynamodb:DescribeStream",
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:ListStreams",
          "dynamodb:ConditionCheckItem",
        ]
        Resource = [
          local.platform_ddb_arn_pattern,
          "${local.platform_ddb_arn_pattern}/index/*",
          "${local.platform_ddb_arn_pattern}/stream/*",
        ]
      },
      {
        Sid       = "VinMappingReadOnly"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:DescribeTable"]
        Resource  = [local.vin_mapping_arn]
      },
    ]
  })

  tags = merge(var.tags, { Name = "${var.prefix}-dynamodb-gw" })
}

# interface endpoints - kinesis streams + firehose
resource "aws_security_group" "kinesis_endpoint" {
  name_prefix = "${var.prefix}-kinesis-ep-"
  vpc_id      = module.vpc.vpc_id
  description = "Kinesis VPC endpoint"
  tags        = merge(var.tags, { Name = "${var.prefix}-kinesis-ep-sg" })
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "kinesis_endpoint_https" {
  security_group_id = aws_security_group.kinesis_endpoint.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS from VPC"
}

resource "aws_vpc_endpoint" "kinesis" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.kinesis-streams"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.kinesis_endpoint.id]
  tags                = merge(var.tags, { Name = "${var.prefix}-kinesis-ep" })
}

resource "aws_vpc_endpoint" "firehose" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.kinesis-firehose"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.kinesis_endpoint.id]
  tags                = merge(var.tags, { Name = "${var.prefix}-firehose-ep" })
}

# -----------------------------------------------------------------------------
# Security groups - rules declared as attachment resources
# (aws_vpc_security_group_*_rule) per best practice.
# -----------------------------------------------------------------------------
resource "aws_security_group" "consumer" {
  name_prefix = "${var.prefix}-consumer-"
  vpc_id      = module.vpc.vpc_id
  description = "Consumer ECS service"
  tags        = merge(var.tags, { Name = "${var.prefix}-consumer-sg" })
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_egress_rule" "consumer_all" {
  security_group_id = aws_security_group.consumer.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}

resource "aws_security_group" "sse" {
  name_prefix = "${var.prefix}-sse-"
  vpc_id      = module.vpc.vpc_id
  description = "SSE ECS service"
  tags        = merge(var.tags, { Name = "${var.prefix}-sse-sg" })
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "sse_from_vpc" {
  security_group_id = aws_security_group.sse.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 3000
  to_port           = 3000
  description       = "NLB health checks and traffic"
}

resource "aws_vpc_security_group_egress_rule" "sse_all" {
  security_group_id = aws_security_group.sse.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}

resource "aws_security_group" "valkey" {
  name_prefix = "${var.prefix}-valkey-"
  vpc_id      = module.vpc.vpc_id
  description = "ElastiCache Valkey"
  tags        = merge(var.tags, { Name = "${var.prefix}-valkey-sg" })
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "valkey_from_consumer" {
  security_group_id            = aws_security_group.valkey.id
  referenced_security_group_id = aws_security_group.consumer.id
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  description                  = "Valkey from Consumer"
}

resource "aws_vpc_security_group_ingress_rule" "valkey_from_sse" {
  security_group_id            = aws_security_group.valkey.id
  referenced_security_group_id = aws_security_group.sse.id
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  description                  = "Valkey from SSE"
}

resource "aws_security_group" "lambda" {
  name_prefix = "${var.prefix}-lambda-"
  vpc_id      = module.vpc.vpc_id
  description = "Lambda functions"
  tags        = merge(var.tags, { Name = "${var.prefix}-lambda-sg" })
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_egress_rule" "lambda_all" {
  security_group_id = aws_security_group.lambda.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}

resource "aws_security_group" "signing_proxy" {
  name_prefix = "${var.prefix}-signing-proxy-"
  vpc_id      = module.vpc.vpc_id
  description = "Signing proxy Lambda - restricted egress"
  tags        = merge(var.tags, { Name = "${var.prefix}-signing-proxy-sg" })
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_egress_rule" "signing_proxy_https" {
  security_group_id = aws_security_group.signing_proxy.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS to OEM Fleet API"
}

resource "aws_vpc_security_group_egress_rule" "signing_proxy_dns" {
  security_group_id = aws_security_group.signing_proxy.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
  description       = "DNS resolution"
}

resource "aws_security_group" "influxdb" {
  name_prefix = "${var.prefix}-influxdb-"
  vpc_id      = module.vpc.vpc_id
  description = "Timestream for InfluxDB"
  tags        = merge(var.tags, { Name = "${var.prefix}-influxdb-sg" })
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "influxdb_from_consumer" {
  security_group_id            = aws_security_group.influxdb.id
  referenced_security_group_id = aws_security_group.consumer.id
  ip_protocol                  = "tcp"
  from_port                    = 8086
  to_port                      = 8086
  description                  = "InfluxDB from Consumer"
}

resource "aws_vpc_security_group_ingress_rule" "influxdb_from_lambda" {
  security_group_id            = aws_security_group.influxdb.id
  referenced_security_group_id = aws_security_group.lambda.id
  ip_protocol                  = "tcp"
  from_port                    = 8086
  to_port                      = 8086
  description                  = "InfluxDB from Lambda"
}

resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "fleet.local"
  description = "Service discovery for ${var.prefix}"
  vpc         = module.vpc.vpc_id
  tags        = var.tags
}
