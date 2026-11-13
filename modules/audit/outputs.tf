output "trail_name" {
  value = aws_cloudtrail.this.name
}

output "trail_bucket_name" {
  value = aws_s3_bucket.trail.bucket
}
