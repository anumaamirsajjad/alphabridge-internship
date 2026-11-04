# Values that differ between runs or environments. Nothing here is a secret: the pipeline's
# database password lives in Secrets Manager, and Terraform never stores it.

variable "region" {
  description = "AWS region for every ETL resource. Must match the database region."
  type        = string
  default     = "ap-south-1"
}

variable "account_id" {
  description = "AWS account ID. Used to make bucket names unique and to build ARNs."
  type        = string
  default     = "169774886945"
}

variable "etl_db_secret_name" {
  description = "Secrets Manager secret holding the read-only database user as JSON: {\"username\": \"...\", \"password\": \"...\"}. Created by hand, see etl/TODO.md."
  type        = string
  default     = "alphabridge/etl-db"
}

variable "database_identifier" {
  description = "RDS instance identifier of the source database (the API database)."
  type        = string
  default     = "alphabridge"
}

variable "database_name" {
  description = "Database name inside the production instance (confirmed from the Flyway output on the live database). docker-compose uses banking_db for local development only."
  type        = string
  default     = "postgres"
}

variable "glue_version" {
  description = "AWS Glue runtime version. 5.0 uses Spark 3.5, which matches requirements-dev.txt."
  type        = string
  default     = "5.0"
}

variable "glue_worker_type" {
  description = "Size of each Glue worker. G.1X is the smallest standard size."
  type        = string
  default     = "G.1X"
}

variable "glue_number_of_workers" {
  description = "Workers per Glue job run. Two is enough for the current table sizes."
  type        = number
  default     = 2
}

variable "schedule_expression" {
  description = "When the pipeline runs (UTC). 19:30 UTC is after the database backup window (17:52 to 18:22 UTC)."
  type        = string
  default     = "cron(30 19 * * ? *)"
}

variable "tables" {
  description = "Source tables the pipeline copies to Bronze each run. accounts is always a full read."
  type        = list(string)
  default     = ["transactions", "refunds", "cancellations", "accounts"]
}
