output "vpc_id" { value = module.vpc.vpc_id }
output "vpc_cidr" { value = module.vpc.vpc_cidr_block }
output "public_subnet_ids" { value = module.vpc.public_subnets }
output "private_subnet_ids" { value = module.vpc.private_subnets }
output "private_route_table_ids" { value = module.vpc.private_route_table_ids }

output "security_group_ids" {
  value = {
    consumer      = aws_security_group.consumer.id
    sse           = aws_security_group.sse.id
    valkey        = aws_security_group.valkey.id
    lambda        = aws_security_group.lambda.id
    signing_proxy = aws_security_group.signing_proxy.id
    influxdb      = aws_security_group.influxdb.id
  }
}

output "cloudmap_namespace_id" {
  value = aws_service_discovery_private_dns_namespace.main.id
}
