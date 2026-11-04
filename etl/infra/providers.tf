# The AWS account and region every ETL resource is created in.

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "alphabridge"
      Component = "etl"
      ManagedBy = "terraform"
    }
  }
}
