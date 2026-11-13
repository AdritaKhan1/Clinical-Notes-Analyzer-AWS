# Phase 3: audit trail.
#
# CloudTrail records who did what in the account (management events, which
# are free for the first trail) plus every read and write of a clinical note
# in the incoming bucket (S3 data events, $0.10 per 100,000 events, so a few
# test sessions round to $0.00). Logs go to their own locked-down bucket.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  trail_name = "${var.project_name}-trail"
  # Built by hand because the bucket policy must exist before the trail does.
  trail_arn = "arn:aws:cloudtrail:${data.aws_region.current.name}:${local.account_id}:trail/${local.trail_name}"
}

resource "aws_s3_bucket" "trail" {
  bucket        = "${var.project_name}-trail-${local.account_id}"
  force_destroy = true # lets terraform destroy remove it with log files inside
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket                  = aws_s3_bucket.trail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3-managed encryption keeps this simple. Using the project KMS key would
# need extra key policy rules for CloudTrail and adds no real benefit here,
# since audit logs hold API activity, not note contents.
resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    id     = "expire-audit-logs"
    status = "Enabled"
    filter {}

    expiration {
      days = var.log_retention_days
    }
  }
}

# Only this one trail in this account may write here, and only over HTTPS.
resource "aws_s3_bucket_policy" "trail" {
  bucket     = aws_s3_bucket.trail.id
  depends_on = [aws_s3_bucket_public_access_block.trail]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "CloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.trail.arn
        Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn } }
      },
      {
        Sid       = "CloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.trail.arn}/AWSLogs/${local.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = local.trail_arn
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.trail.arn, "${aws_s3_bucket.trail.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })
}

resource "aws_cloudtrail" "this" {
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.trail.id
  is_multi_region_trail         = false
  include_global_service_events = true
  enable_log_file_validation    = true # proves log files weren't edited after delivery

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    # Every upload and every read of a clinical note is recorded.
    data_resource {
      type   = "AWS::S3::Object"
      values = ["${var.incoming_bucket_arn}/notes/"]
    }
  }

  depends_on = [aws_s3_bucket_policy.trail]
}
