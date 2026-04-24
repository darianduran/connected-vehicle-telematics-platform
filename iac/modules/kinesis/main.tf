resource "aws_kinesis_stream" "telemetry" {
  name = "${var.prefix}-telemetry"

  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  retention_period = 24
  encryption_type  = "KMS"
  kms_key_id       = var.telemetry_kms_key_id

  tags = var.tags
}
