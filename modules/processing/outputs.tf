output "function_name" {
  value = aws_lambda_function.processor.function_name
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}

output "dlq_name" {
  value = aws_sqs_queue.dlq.name
}
