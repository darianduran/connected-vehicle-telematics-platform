variable "prefix" { type = string }

variable "telemetry_kms_key_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
