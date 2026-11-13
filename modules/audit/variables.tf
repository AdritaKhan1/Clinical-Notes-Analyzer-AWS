variable "project_name" {
  type = string
}

variable "incoming_bucket_arn" {
  type = string
}

variable "log_retention_days" {
  description = "Audit log files are deleted after this many days."
  type        = number
  default     = 30
}
