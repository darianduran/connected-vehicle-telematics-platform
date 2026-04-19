module "networking" {
  source             = "./modules/networking"
  prefix             = local.prefix
  vpc_cidr           = var.vpc_cidr
  aws_region         = var.aws_region
  single_nat_gateway = var.single_nat_gateway
  tags               = local.common_tags
}

module "kms" {
  source = "./modules/kms"
  prefix = local.prefix
  tags   = local.common_tags
}

module "dynamodb" {
  source                     = "./modules/dynamodb"
  prefix                     = local.prefix
  enable_deletion_protection = var.enable_deletion_protection
  enable_global_tables       = var.enable_global_tables
  dr_region                  = var.dr_region
  tags                       = local.common_tags
}

module "s3" {
  source           = "./modules/s3"
  prefix           = local.prefix
  data_kms_key_arn = module.kms.data_key_arn
  enable_crr       = local.enable_s3_crr_effective
  dr_region        = var.dr_region
  tags             = local.common_tags

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }
}

module "secrets" {
  source = "./modules/secrets"
  prefix = local.prefix
  tags   = local.common_tags
}

module "kinesis" {
  source               = "./modules/kinesis"
  prefix               = local.prefix
  telemetry_kms_key_id = module.kms.telemetry_key_id
  tags                 = local.common_tags
}

module "firehose" {
  source                = "./modules/firehose"
  prefix                = local.prefix
  data_kms_key_arn      = module.kms.data_key_arn
  telemetry_kms_key_arn = module.kms.telemetry_key_arn
  telemetry_bucket_arn  = module.s3.telemetry_bucket_arn
  telemetry_bucket_id   = module.s3.telemetry_bucket_id
  tags                  = local.common_tags
}

module "iot_core" {
  source              = "./modules/iot-core"
  prefix              = local.prefix
  kinesis_stream_arn  = module.kinesis.stream_arn
  kinesis_stream_name = module.kinesis.stream_name
  alarm_sns_topic_arn = module.sqs_sns.sns_topic_arns["security_alerts"]
  enable_alarms       = true
  tags                = local.common_tags
}

module "elasticache" {
  source             = "./modules/elasticache"
  prefix             = local.prefix
  private_subnet_ids = module.networking.private_subnet_ids
  security_group_id  = module.networking.security_group_ids["valkey"]
  auth_token         = module.secrets.valkey_auth_token
  enable_multi_az    = var.enable_valkey_multi_az
  tags               = local.common_tags
}

module "influxdb" {
  source             = "./modules/influxdb"
  prefix             = local.prefix
  private_subnet_ids = module.networking.private_subnet_ids
  security_group_id  = module.networking.security_group_ids["influxdb"]
  admin_password     = module.secrets.influxdb_admin_password
  logs_bucket_id     = module.s3.bucket_ids["logs"]
  tags               = local.common_tags
}

module "sqs_sns" {
  source          = "./modules/sqs_sns"
  prefix          = local.prefix
  data_kms_key_id = module.kms.data_key_id
  tags            = local.common_tags
}

module "iam" {
  source                           = "./modules/iam"
  prefix                           = local.prefix
  kinesis_stream_arn               = module.kinesis.stream_arn
  firehose_stream_arn              = module.firehose.delivery_stream_arn
  telemetry_kms_key_arn            = module.kms.telemetry_key_arn
  data_kms_key_arn                 = module.kms.data_key_arn
  dynamodb_table_arns              = module.dynamodb.table_arns
  s3_bucket_arns                   = module.s3.bucket_arns
  sqs_queue_arns                   = module.sqs_sns.sqs_queue_arns
  sns_topic_arns                   = module.sqs_sns.sns_topic_arns
  secrets_arns                     = module.secrets.secret_arns
  ssm_parameter_arns               = { for k, v in aws_ssm_parameter.config : k => v.arn }
  vin_mapping_admin_principal_arns = var.vin_mapping_admin_principal_arns
  tags                             = local.common_tags
}

module "lambda" {
  source                            = "./modules/lambda"
  prefix                            = local.prefix
  aws_region                        = var.aws_region
  private_subnet_ids                = module.networking.private_subnet_ids
  lambda_security_group_id          = module.networking.security_group_ids["lambda"]
  signing_proxy_security_group_id   = module.networking.security_group_ids["signing_proxy"]
  lambda_role_arns                  = module.iam.lambda_role_arns
  dynamodb_table_names              = module.dynamodb.table_names
  s3_bucket_ids                     = module.s3.bucket_ids
  sqs_queue_arns                    = module.sqs_sns.sqs_queue_arns
  sns_topic_arns                    = module.sqs_sns.sns_topic_arns
  secrets_arns                      = module.secrets.secret_arns
  trip_history_stream_arn           = module.dynamodb.trip_history_stream_arn
  cloudfront_domain                 = var.domain_name
  cloudfront_key_pair_id            = var.cloudfront_key_pair_id
  cloudfront_private_key_secret_arn = var.cloudfront_private_key_secret_arn
  influxdb_endpoint                 = module.influxdb.endpoint
  tags                              = local.common_tags
}

module "cognito" {
  source               = "./modules/cognito"
  prefix               = local.prefix
  domain_name          = var.domain_name
  pre_token_lambda_arn = module.lambda.cognito_pre_token_arn
  tags                 = local.common_tags
}

# push cognito ids into SSM so the lambdas can grab them at runtime
resource "aws_ssm_parameter" "cognito_user_pool_id" {
  name  = "/${local.prefix}/config/cognito_user_pool_id"
  type  = "String"
  value = module.cognito.user_pool_id
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "cognito_client_id" {
  name  = "/${local.prefix}/config/cognito_client_id"
  type  = "String"
  value = module.cognito.client_id
  tags  = local.common_tags
}

module "ecs" {
  source                     = "./modules/ecs"
  prefix                     = local.prefix
  aws_region                 = var.aws_region
  vpc_id                     = module.networking.vpc_id
  private_subnet_ids         = module.networking.private_subnet_ids
  public_subnet_ids          = module.networking.public_subnet_ids
  consumer_security_group_id = module.networking.security_group_ids["consumer"]
  sse_security_group_id      = module.networking.security_group_ids["sse"]
  task_execution_role_arn    = module.iam.ecs_task_execution_role_arn
  consumer_task_role_arn     = module.iam.consumer_task_role_arn
  sse_task_role_arn          = module.iam.sse_server_task_role_arn
  kinesis_stream_name        = module.kinesis.stream_name
  valkey_endpoint            = module.elasticache.primary_endpoint
  valkey_port                = module.elasticache.port
  firehose_stream_name       = module.firehose.delivery_stream_name
  dynamodb_table_names       = module.dynamodb.table_names
  s3_telemetry_bucket        = module.s3.bucket_ids["telemetry"]
  sqs_geofence_check_url     = module.sqs_sns.sqs_queue_urls["geofence_check"]
  sns_critical_alerts_arn    = module.sqs_sns.sns_topic_arns["critical_alerts"]
  sns_crash_emergency_arn    = module.sqs_sns.sns_topic_arns["crash_emergency"]
  vin_hmac_key_secret_arn    = module.secrets.secret_arns["vin_hmac_key"]
  valkey_auth_secret_arn     = module.secrets.secret_arns["valkey_auth"]
  session_secret_arn         = module.secrets.secret_arns["session"]
  cognito_user_pool_id       = module.cognito.user_pool_id
  cognito_client_id          = module.cognito.client_id
  frontend_origins           = "https://${var.domain_name}"
  deploy_services            = var.deploy_ecs_services
  nlb_certificate_arn        = module.acm.acm_certificate_arn
  image_tags = {
    consumer   = var.image_tag_consumer
    sse-server = var.image_tag_sse_server
  }
  tags = local.common_tags
}

module "security" {
  source                 = "./modules/security"
  prefix                 = local.prefix
  security_sns_topic_arn = module.sqs_sns.sns_topic_arns["security_alerts"]
  data_kms_key_arn       = module.kms.data_key_arn
  data_kms_key_id        = module.kms.data_key_id
  enable_data_events     = true
  enable_crr             = local.enable_s3_crr_effective
  s3_bucket_arns = [
    "${module.s3.bucket_arns["telemetry"]}/*",
    "${module.s3.bucket_arns["dashcam"]}/*"
  ]
  dynamodb_table_arns = [
    module.dynamodb.table_arns["vin_mapping"]
  ]
  tags = local.common_tags

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }
}

module "eventbridge" {
  source = "./modules/eventbridge"
  prefix = local.prefix
  lambda_arns = {
    stale_trip_cleanup     = module.lambda.function_arns["stale_trip_cleanup"]
    predictive_maintenance = module.lambda.function_arns["predictive_maintenance"]
    cognito_export         = module.lambda.function_arns["cognito_export"]
    influxdb_backup        = module.lambda.function_arns["influxdb_backup"]
    oem_command_proxy      = module.lambda.function_arns["oem_command_proxy"]
  }
  dashcam_bucket_id     = module.s3.bucket_ids["dashcam"]
  dashcam_sqs_queue_arn = module.sqs_sns.sqs_queue_arns["dashcam_processing"]
  dashcam_sqs_queue_url = module.sqs_sns.sqs_queue_urls["dashcam_processing"]
  tags                  = local.common_tags
}

module "cloudwatch" {
  source                      = "./modules/cloudwatch"
  prefix                      = local.prefix
  critical_sns_topic_arn      = module.sqs_sns.sns_topic_arns["critical_alerts"]
  kinesis_stream_name         = module.kinesis.stream_name
  dynamodb_table_names        = module.dynamodb.table_names
  lambda_function_names       = { for k, arn in module.lambda.function_arns : k => reverse(split(":", arn))[0] }
  ecs_cluster_name            = "${local.prefix}-cluster"
  ecs_service_names           = var.deploy_ecs_services ? { consumer = "${local.prefix}-consumer", sse_server = "${local.prefix}-sse-server" } : {}
  valkey_replication_group_id = "${local.prefix}-valkey"
  firehose_stream_name        = module.firehose.delivery_stream_name
  sqs_dlq_names = {
    geofence_check_dlq     = "${local.prefix}-geofence-check-dlq.fifo"
    dashcam_processing_dlq = "${local.prefix}-dashcam-processing-dlq"
  }
  nlb_arn_suffix              = module.ecs.nlb_arn_suffix
  nlb_target_group_arn_suffix = module.ecs.sse_target_group_arn_suffix
  tags                        = local.common_tags
}

# Enable or disable in variables.tf and only apply from the management account

module "scp" {
  count  = var.manage_scps ? 1 : 0
  source = "./modules/scp"

  prefix          = local.prefix
  target_ids      = var.scp_target_ids
  allowed_regions = [var.aws_region, var.dr_region]
  tags            = local.common_tags
}

