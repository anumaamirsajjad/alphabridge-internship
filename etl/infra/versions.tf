# Pins the Terraform and AWS provider versions, and stores the ETL state in the same S3 bucket
# as the API stack, under its own key. So the ETL stack can never change API resources.

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
    key          = "alphabridge-etl/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
