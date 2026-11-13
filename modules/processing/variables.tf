variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "lambda_security_group_id" {
  type = string
}

variable "endpoints_security_group_id" {
  type = string
}

variable "incoming_bucket_name" {
  type = string
}

variable "incoming_bucket_arn" {
  type = string
}

variable "results_table_name" {
  type = string
}

variable "results_table_arn" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "alert_email" {
  type = string
}

variable "flag_conditions" {
  type = list(string)
}

variable "flag_medications" {
  type = list(string)
}

variable "max_note_chars" {
  type = number
}
