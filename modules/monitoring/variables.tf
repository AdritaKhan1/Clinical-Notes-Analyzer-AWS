variable "project_name" {
  type = string
}

variable "function_name" {
  type = string
}

variable "dlq_name" {
  type = string
}

variable "alerts_topic_arn" {
  type = string
}

variable "slow_threshold_ms" {
  description = "Alarm when a single run takes longer than this (Lambda timeout is 60,000 ms)."
  type        = number
  default     = 45000
}
