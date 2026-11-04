# Pins the Terraform and AWS provider versions for the real-time events stack. It has its own
# state key, so it cannot change the API or the ETL stacks.

terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.80.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "2.7.1"
    }
  }

  backend "s3" {
    bucket       = "alphabridge-tfstate-169774886945"
    key          = "alphabridge-realtime/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
