terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.region

  # Every resource gets these tags, which makes it easy to see
  # what this project created (and what it costs) in the console.
  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      DataType  = "synthetic"
    }
  }
}
