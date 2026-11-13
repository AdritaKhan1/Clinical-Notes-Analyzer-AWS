# Phase 3: alarms that email you when the pipeline misbehaves.
#
# Four alarms, all inside CloudWatch's free allowance of 10. They publish to
# the same encrypted SNS topic as the flagged-note alerts, which is why the
# KMS key policy lets CloudWatch use the key.

locals {
  common = {
    period              = 300
    evaluation_periods  = 1
    treat_missing_data  = "notBreaching" # no data means nothing happened, not a problem
    comparison_operator = "GreaterThanOrEqualToThreshold"
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name        = "${var.project_name}-lambda-errors"
  alarm_description = "A note failed to process. It will be retried twice, then sent to the dead-letter queue."
  namespace         = "AWS/Lambda"
  metric_name       = "Errors"
  statistic         = "Sum"
  threshold         = 1
  dimensions        = { FunctionName = var.function_name }

  period              = local.common.period
  evaluation_periods  = local.common.evaluation_periods
  treat_missing_data  = local.common.treat_missing_data
  comparison_operator = local.common.comparison_operator
  alarm_actions       = [var.alerts_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name        = "${var.project_name}-dlq-not-empty"
  alarm_description = "At least one note gave up after all retries and is waiting in the dead-letter queue."
  namespace         = "AWS/SQS"
  metric_name       = "ApproximateNumberOfMessagesVisible"
  statistic         = "Maximum"
  threshold         = 1
  dimensions        = { QueueName = var.dlq_name }

  period              = local.common.period
  evaluation_periods  = local.common.evaluation_periods
  treat_missing_data  = local.common.treat_missing_data
  comparison_operator = local.common.comparison_operator
  alarm_actions       = [var.alerts_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "lambda_slow" {
  alarm_name        = "${var.project_name}-lambda-slow"
  alarm_description = "A note took over 75% of the 60 second timeout. Usually a network or endpoint problem."
  namespace         = "AWS/Lambda"
  metric_name       = "Duration"
  statistic         = "Maximum"
  threshold         = var.slow_threshold_ms
  dimensions        = { FunctionName = var.function_name }

  period              = local.common.period
  evaluation_periods  = local.common.evaluation_periods
  treat_missing_data  = local.common.treat_missing_data
  comparison_operator = local.common.comparison_operator
  alarm_actions       = [var.alerts_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name        = "${var.project_name}-lambda-throttles"
  alarm_description = "Lambda refused to run because of concurrency limits."
  namespace         = "AWS/Lambda"
  metric_name       = "Throttles"
  statistic         = "Sum"
  threshold         = 1
  dimensions        = { FunctionName = var.function_name }

  period              = local.common.period
  evaluation_periods  = local.common.evaluation_periods
  treat_missing_data  = local.common.treat_missing_data
  comparison_operator = local.common.comparison_operator
  alarm_actions       = [var.alerts_topic_arn]
}
