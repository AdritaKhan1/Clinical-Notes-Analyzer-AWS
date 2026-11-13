# Phase 1: network + storage.
# Phase 2: Lambda, Comprehend Medical + SNS endpoints, alerts, dead-letter queue.
# Phase 3: CloudTrail audit trail, CloudWatch alarms, tighter IAM and endpoint
#          policies (see lockdown.tf).
#
# The monthly budget alert is no longer created here. It lives in the AWS
# console instead, so it keeps watching costs after terraform destroy.

module "network" {
  source       = "./modules/network"
  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr
}

module "storage" {
  source         = "./modules/storage"
  project_name   = var.project_name
  s3_endpoint_id = module.network.s3_endpoint_id
}

module "processing" {
  source       = "./modules/processing"
  project_name = var.project_name

  vpc_id                      = module.network.vpc_id
  private_subnet_ids          = module.network.private_subnet_ids
  lambda_security_group_id    = module.network.lambda_security_group_id
  endpoints_security_group_id = module.network.endpoints_security_group_id

  incoming_bucket_name = module.storage.incoming_bucket_name
  incoming_bucket_arn  = module.storage.incoming_bucket_arn
  results_table_name   = module.storage.results_table_name
  results_table_arn    = module.storage.results_table_arn
  kms_key_arn          = module.storage.kms_key_arn

  alert_email      = var.alert_email
  flag_conditions  = var.flag_conditions
  flag_medications = var.flag_medications
  max_note_chars   = var.max_note_chars
}

module "audit" {
  source              = "./modules/audit"
  project_name        = var.project_name
  incoming_bucket_arn = module.storage.incoming_bucket_arn
}

module "monitoring" {
  source           = "./modules/monitoring"
  project_name     = var.project_name
  function_name    = module.processing.function_name
  dlq_name         = module.processing.dlq_name
  alerts_topic_arn = module.processing.alerts_topic_arn
}
