# Values for the real-time events stack. Nothing here is a secret.

variable "region" {
  description = "AWS region. Must match the rest of the project."
  type        = string
  default     = "ap-south-1"
}

variable "max_receive_count" {
  description = "How many times a message may fail before it moves to the dead-letter queue."
  type        = number
  default     = 5
}

variable "account_id" {
  description = "AWS account ID. Used to find the gold bucket by name."
  type        = string
  default     = "169774886945"
}

variable "large_transaction_threshold" {
  description = "Transfers at or above this amount are flagged. PLACEHOLDER until the business confirms it."
  type        = string
  default     = "10000"
}

variable "lambda_timeout_seconds" {
  description = "Lambda timeout. Must be shorter than the queue's visibility timeout."
  type        = number
  default     = 30
}

variable "visibility_timeout_seconds" {
  description = "How long a message stays hidden while the Lambda works on it. Must be longer than the Lambda timeout."
  type        = number
  default     = 60
}
