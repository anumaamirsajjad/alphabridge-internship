# The AWS account and region for the real-time events stack.

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "alphabridge"
      Component = "realtime"
      ManagedBy = "terraform"
    }
  }
}
