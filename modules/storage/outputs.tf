output "incoming_bucket_name" {
  value = aws_s3_bucket.incoming.bucket
}

output "incoming_bucket_arn" {
  value = aws_s3_bucket.incoming.arn
}

output "results_table_name" {
  value = aws_dynamodb_table.results.name
}

output "results_table_arn" {
  value = aws_dynamodb_table.results.arn
}

output "kms_key_arn" {
  value = aws_kms_key.this.arn
}
