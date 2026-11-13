output "vpc_id" {
  value = module.network.vpc_id
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "incoming_bucket" {
  description = "Upload synthetic notes here."
  value       = module.storage.incoming_bucket_name
}

output "results_table" {
  value = module.storage.results_table_name
}

output "kms_key_arn" {
  value = module.storage.kms_key_arn
}

output "function_name" {
  value = module.processing.function_name
}

output "dlq_url" {
  description = "Notes that failed processing end up here."
  value       = module.processing.dlq_url
}

output "dlq_name" {
  value = module.processing.dlq_name
}

output "trail_bucket" {
  description = "CloudTrail audit logs land here (5 to 15 minutes after the activity)."
  value       = module.audit.trail_bucket_name
}

output "alarm_names" {
  value = module.monitoring.alarm_names
}
