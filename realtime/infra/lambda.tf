# The Lambda that reads transfer events from the queue and writes them to the gold bucket.
#
# It reads the gold bucket and the lake key by name. Both are created by the ETL stack
# (etl/infra), so apply the ETL stack first.

data "aws_s3_bucket" "gold" {
  bucket = "alphabridge-lake-gold-${var.account_id}"
}

data "aws_kms_alias" "lake" {
  name = "alias/alphabridge-etl"
}

data "archive_file" "handler" {
  type        = "zip"
  source_file = "${path.module}/../lambda/handler.py"
  output_path = "${path.module}/build/handler.zip"
}

resource "aws_cloudwatch_log_group" "handler" {
  name              = "/aws/lambda/alphabridge-transaction-events"
  retention_in_days = 30
}

resource "aws_lambda_function" "handler" {
  function_name    = "alphabridge-transaction-events"
  role             = aws_iam_role.handler.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.handler.output_path
  source_code_hash = data.archive_file.handler.output_base64sha256
  timeout          = var.lambda_timeout_seconds
  memory_size      = 256

  environment {
    variables = {
      GOLD_BUCKET                 = data.aws_s3_bucket.gold.bucket
      LARGE_TRANSACTION_THRESHOLD = var.large_transaction_threshold
    }
  }

  depends_on = [aws_cloudwatch_log_group.handler]
}

# Reads from the queue in batches. A batch can wait up to 30 seconds to fill, which keeps the
# insights within about a minute of the transfer. Failed messages are reported back one by one.
resource "aws_lambda_event_source_mapping" "events" {
  event_source_arn                   = aws_sqs_queue.events.arn
  function_name                      = aws_lambda_function.handler.arn
  batch_size                         = 100
  maximum_batching_window_in_seconds = 30
  function_response_types            = ["ReportBatchItemFailures"]
}
