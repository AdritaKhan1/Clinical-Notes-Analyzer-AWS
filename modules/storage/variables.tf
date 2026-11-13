variable "project_name" {
  type = string
}

variable "s3_endpoint_id" {
  description = "Raw notes can only be read through this VPC endpoint."
  type        = string
}
