output "tfstate_bucket" {
  value = aws_s3_bucket.tfstate.id
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}
