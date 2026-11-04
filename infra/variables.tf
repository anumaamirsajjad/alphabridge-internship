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

# Blue/green: there are two complete app environments, "blue" and "green". Only the one named in
# live_color receives customer traffic. A new release is started on the other one, tested, then
# switched to by changing live_color. See infra/README.md ("Blue/green deploys").

variable "live_color" {
  description = "Which environment serves traffic: \"blue\" or \"green\". Changing it is the cutover, and changing it back is the rollback."
  type        = string
  default     = "blue"

  validation {
    condition     = contains(["blue", "green"], var.live_color)
    error_message = "live_color must be \"blue\" or \"green\"."
  }
}

variable "blue_image_tag" {
  description = "Container image tag for the blue environment, for example the Git commit ID. Keep it equal to the live tag while blue is live."
  type        = string
}

variable "green_image_tag" {
  description = "Container image tag for the green environment, for example the Git commit ID."
  type        = string
}

variable "blue_capacity" {
  description = "How many servers the blue environment runs. 0 switches it off."
  type        = number
  default     = 2
}

variable "green_capacity" {
  description = "How many servers the green environment runs. 0 switches it off."
  type        = number
  default     = 0
}

variable "app_server_max" {
  description = "The most servers each environment may run. Leaves room for a rolling refresh to add one first."
  type        = number
  default     = 3
}

variable "deploy_test_header_value" {
  description = "Optional. When set, requests carrying the header X-Deploy-Test with this value reach the idle environment, so it can be tested before the cutover. Leave empty to turn the test route off. Pass it with -var or an environment variable, not in the committed tfvars file."
  type        = string
  default     = ""
  sensitive   = true
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
