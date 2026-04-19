locals {
  prefix = "${var.app}-${var.env}"

  common_tags = {
    Environment = var.env
    Project     = var.app
    CostCenter  = var.cost_center
    Owner       = var.owner
    ManagedBy   = "Terraform"
  }


  ssm_runtime_parameters = {
    consumer_kinesis_iterator_type        = "LATEST"
    consumer_batch_records                = "500"
    consumer_checkpoint_interval_seconds  = "60"
    consumer_checkpoint_record_threshold  = "500"
    consumer_poll_interval_ms             = "1000"
    consumer_gap_seconds                  = "300"
    consumer_trip_start_speed_mph         = "5.0"
    consumer_trip_end_speed_mph           = "1.0"
    consumer_speed_limit_mph              = "85.0"
    sse_node_env                          = "production"
    trip_processor_speeding_threshold_mph = "85"
    trip_processor_hard_brake_g           = "-0.45"
    trip_processor_hard_accel_g           = "0.40"
    trip_processor_agg_turn_g             = "0.40"
    fallback_orphan_threshold_minutes     = "10"
    signing_proxy_cache_size              = "100"
    signing_proxy_timeout                 = "10"
    access_token_expiry_minutes           = "15"
    signed_url_expiry_minutes             = "15"
  }
}
