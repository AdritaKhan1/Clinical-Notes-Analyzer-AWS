output "alarm_names" {
  value = [
    aws_cloudwatch_metric_alarm.lambda_errors.alarm_name,
    aws_cloudwatch_metric_alarm.dlq_not_empty.alarm_name,
    aws_cloudwatch_metric_alarm.lambda_slow.alarm_name,
    aws_cloudwatch_metric_alarm.lambda_throttles.alarm_name,
  ]
}
