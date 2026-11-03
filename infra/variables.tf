# Values that change between runs or environments. Set them in terraform.tfvars, or
# pass them from the pipeline with -var. Nothing here is a secret: the database password
# stays in Secrets Manager.

variable "region" {
  description = "AWS region for every resource."
  type        = string
  default     = "ap-south-1"
}

variable "account_id" {
  description = "AWS account ID. Used to build ARNs and image addresses."
  type        = string
  default     = "169774886945"
}

variable "image_tag" {
  description = "Container image tag to run, for example the Git commit ID. The pipeline sets this on each deploy."
  type        = string
  default     = "step2"
}

variable "app_server_count" {
  description = "How many app servers the auto scaling group keeps running."
  type        = number
  default     = 2
}

variable "app_server_max" {
  description = "The most app servers the auto scaling group may run. Leaves room for a deploy to add one first."
  type        = number
  default     = 3
}

variable "instance_type" {
  description = "EC2 size for the app servers."
  type        = string
  default     = "t3.small"
}

variable "events_enabled" {
  description = "Lets the API send transfer.created events to the queue. Turn on only after the realtime stack (realtime/infra) has been applied, because the queue is looked up by name."
  type        = bool
  default     = false
}

variable "events_queue_name" {
  description = "Name of the events queue, created by the realtime stack."
  type        = string
  default     = "alphabridge-transaction-events"
}

variable "etl_access_enabled" {
  description = "Lets the ETL Glue workers reach the database on port 5432. Turn on only after the ETL network (etl/infra) has been applied, because the rule looks up its security group by name."
  type        = bool
  default     = false
}
