# Encrypted storage for incoming notes (S3) and processed results (DynamoDB).

data "aws_caller_identity" "current" {}

# One customer-managed key encrypts everything in this project.
# Costs about $1/month while it exists.
resource "aws_kms_key" "this" {
  description             = "${var.project_name} encryption key"
  enable_key_rotation     = true
  deletion_window_in_days = 7 # shortest allowed, so destroy cleans up quickly

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Same as AWS's default key policy: IAM permissions in this account
        # decide who can use the key. Removing this would lock you out.
        Sid       = "AccountIamControlsAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        # Phase 3: lets CloudWatch alarms publish to the encrypted SNS topic.
        # Without this, alarms fire but the email silently never arrives.
        Sid       = "CloudWatchAlarmsToEncryptedTopic"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.project_name}"
  target_key_id = aws_kms_key.this.key_id
}

# ---------- S3: incoming notes ----------

resource "aws_s3_bucket" "incoming" {
  # Account ID makes the bucket name globally unique.
  bucket        = "${var.project_name}-incoming-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # lets terraform destroy remove it even with test files inside
}

resource "aws_s3_bucket_public_access_block" "incoming" {
  bucket                  = aws_s3_bucket.incoming.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "incoming" {
  bucket = aws_s3_bucket.incoming.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "incoming" {
  bucket = aws_s3_bucket.incoming.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.this.arn
    }
    bucket_key_enabled = true # cuts KMS request costs
  }
}

# Delete raw notes after 30 days. Keeping identifiable data only as long
# as needed is a good healthcare habit to talk about in interviews.
resource "aws_s3_bucket_lifecycle_configuration" "incoming" {
  bucket = aws_s3_bucket.incoming.id

  rule {
    id     = "expire-raw-notes"
    status = "Enabled"
    filter {}

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# Refuse any request that isn't over HTTPS, and (Phase 3) refuse to hand out
# raw notes to anyone outside the private VPC, even an admin. You can still
# upload from your laptop; you just can't download a note from it.
resource "aws_s3_bucket_policy" "incoming" {
  bucket = aws_s3_bucket.incoming.id

  depends_on = [aws_s3_bucket_public_access_block.incoming]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.incoming.arn,
          "${aws_s3_bucket.incoming.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
      {
        Sid       = "DenyReadingNotesOutsideVpc"
        Effect    = "Deny"
        Principal = "*"
        Action    = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource  = "${aws_s3_bucket.incoming.arn}/*"
        Condition = {
          StringNotEquals = { "aws:SourceVpce" = var.s3_endpoint_id }
        }
      }
    ]
  })
}

# ---------- DynamoDB: de-identified results ----------

resource "aws_dynamodb_table" "results" {
  name         = "${var.project_name}-results"
  billing_mode = "PAY_PER_REQUEST" # no cost when idle

  hash_key  = "patient_id"
  range_key = "note_id"

  attribute {
    name = "patient_id"
    type = "S"
  }

  attribute {
    name = "note_id"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.this.arn
  }

  point_in_time_recovery {
    enabled = true
  }
}
