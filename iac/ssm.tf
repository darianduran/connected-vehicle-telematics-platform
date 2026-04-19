resource "aws_ssm_parameter" "config" {
  for_each = local.ssm_runtime_parameters

  name        = "/${local.prefix}/config/${each.key}"
  description = "Runtime config: ${each.key}"
  type        = "String"
  value       = each.value

  tags = local.common_tags
}
