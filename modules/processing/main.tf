# Phase 2: the part that actually reads notes.
#
# S3 upload -> Lambda (inside the private VPC) -> Comprehend Medical
#           -> DynamoDB results, SNS email if flagged, SQS if it fails

data "aws_region" "current" {}

locals {
  function_name = "${var.project_name}-processor"
}

# ---------- Private hallways to Comprehend Medical and SNS ----------
# Interface endpoints are billed per hour per subnet (~$0.011/hr each in
# ca-central-1). Putting them in ONE subnet halves the cost. Lambda in the
# other subnet can still reach them. Run terraform destroy when not working.

resource "aws_vpc_endpoint" "comprehendmedical" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.comprehendmedical"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [var.private_subnet_ids[0]]
  security_group_ids  = [var.endpoints_security_group_id]
  private_dns_enabled = true

  tags = { Name = "${var.project_name}-comprehendmedical-endpoint" }
}

resource "aws_vpc_endpoint" "sns" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.sns"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [var.private_subnet_ids[0]]
  security_group_ids  = [var.endpoints_security_group_id]
  private_dns_enabled = true

  # Phase 3: this private hallway only leads to our one alerts topic.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.alerts.arn
    }]
  })

  tags = { Name = "${var.project_name}-sns-endpoint" }
}

# ---------- Alerts ----------

resource "aws_sns_topic" "alerts" {
  name              = "${var.project_name}-alerts"
  kms_master_key_id = var.kms_key_arn
}

# AWS emails a confirmation link. Alerts only arrive after you click it.
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------- Failed notes land here instead of disappearing ----------

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.project_name}-dlq"
  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = true
}

# ---------- Lambda permissions (least privilege) ----------

resource "aws_iam_role" "lambda" {
  name = "${local.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Phase 3: replaces the AWS managed policy AWSLambdaVPCAccessExecutionRole,
# which allowed writing logs to ANY log group. Now Lambda can only write to
# its own log group. The EC2 network-interface actions still need "*",
# because Lambda creates those interfaces before their IDs exist.
resource "aws_iam_role_policy" "lambda" {
  name = "${local.function_name}-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadIncomingNotes"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${var.incoming_bucket_arn}/notes/*"
      },
      {
        Sid      = "WriteResults"
        Effect   = "Allow"
        Action   = "dynamodb:PutItem"
        Resource = var.results_table_arn
      },
      {
        Sid      = "SendAlerts"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.alerts.arn
      },
      {
        Sid      = "FailedNotesToDLQ"
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.dlq.arn
      },
      {
        # Comprehend Medical doesn't support resource-level permissions,
        # so "*" is required, but only these two actions are allowed.
        Sid      = "AnalyzeText"
        Effect   = "Allow"
        Action   = ["comprehendmedical:DetectPHI", "comprehendmedical:DetectEntitiesV2"]
        Resource = "*"
      },
      {
        Sid      = "UseProjectKey"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource = var.kms_key_arn
      },
      {
        Sid      = "WriteOwnLogsOnly"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
      },
      {
        Sid    = "VpcNetworkInterfaces"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSubnets",
          "ec2:DeleteNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses",
        ]
        Resource = "*"
      }
    ]
  })
}

# ---------- The function ----------

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.root}/lambda"
  output_path = "${path.root}/build/lambda.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 14
}

resource "aws_lambda_function" "processor" {
  function_name    = local.function_name
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 60
  memory_size      = 256
  kms_key_arn      = var.kms_key_arn # encrypts the environment variables

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  environment {
    variables = {
      TABLE_NAME       = var.results_table_name
      TOPIC_ARN        = aws_sns_topic.alerts.arn
      FLAG_CONDITIONS  = join(",", var.flag_conditions)
      FLAG_MEDICATIONS = join(",", var.flag_medications)
      MAX_CHARS        = tostring(var.max_note_chars)
    }
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  depends_on = [
    aws_iam_role_policy.lambda,
    aws_cloudwatch_log_group.lambda,
  ]
}

# Retry failed notes twice, then send them to the DLQ.
resource "aws_lambda_function_event_invoke_config" "processor" {
  function_name          = aws_lambda_function.processor.function_name
  maximum_retry_attempts = 2
}

# ---------- Wire S3 uploads to the function ----------

resource "aws_lambda_permission" "s3" {
  statement_id   = "AllowS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.processor.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = var.incoming_bucket_arn
  source_account = data.aws_caller_identity.current.account_id
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_notification" "incoming" {
  bucket = var.incoming_bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "notes/"
    filter_suffix       = ".txt"
  }

  depends_on = [aws_lambda_permission.s3]
}
