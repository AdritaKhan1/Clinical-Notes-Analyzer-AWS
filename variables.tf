variable "region" {
  description = "AWS region. ca-central-1 keeps data in Canada and supports Comprehend Medical."
  type        = string
  default     = "ca-central-1"
}

variable "project_name" {
  description = "Short name used as a prefix for every resource."
  type        = string
  default     = "clinical-notes"
}

variable "vpc_cidr" {
  description = "IP range for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "alert_email" {
  description = "Email that receives flagged-note alerts and CloudWatch alarms."
  type        = string
}

variable "flag_conditions" {
  description = "Conditions that trigger an email alert (lowercase, partial matches count)."
  type        = list(string)
  default     = ["chest pain", "myocardial infarction", "sepsis", "stroke", "pulmonary embolism"]
}

variable "flag_medications" {
  description = "High-risk medications that trigger an email alert."
  type        = list(string)
  default     = ["warfarin", "insulin", "heparin", "digoxin", "methotrexate"]
}

variable "max_note_chars" {
  description = "Notes longer than this are rejected to keep Comprehend Medical costs predictable."
  type        = number
  default     = 5000
}

variable "monthly_budget_usd" {
  description = "No longer used. The budget now lives in the AWS console so it survives terraform destroy. Kept so older terraform.tfvars files still work."
  type        = number
  default     = 10
}
