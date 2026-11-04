# The event queue. The API puts one message on it per saved transaction. The Lambda reads from it.
#
# A message that keeps failing is moved to the dead-letter queue (DLQ) after max_receive_count
# attempts. The DLQ keeps it for 14 days, so it can be inspected and replayed.

resource "aws_sqs_queue" "dead_letter" {
  name                      = "alphabridge-transaction-events-dlq"
  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "events" {
  name                       = "alphabridge-transaction-events"
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = 345600 # 4 days
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dead_letter.arn
    maxReceiveCount     = var.max_receive_count
  })
}

# Any message in the DLQ means an event failed every retry, so a person should look at it.
resource "aws_cloudwatch_metric_alarm" "dead_letter_not_empty" {
  alarm_name          = "alphabridge-transaction-events-dlq-not-empty"
  alarm_description   = "A transaction event failed every retry and is in the dead-letter queue"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dead_letter.name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
}
