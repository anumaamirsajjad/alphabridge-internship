# What the Lambda may do. Nothing more.
#
#   - read and delete messages on the events queue
#   - write files under realtime/ in the gold bucket (not the other gold tables)
#   - use the lake key to encrypt those files
#   - write its own logs

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "handler" {
  name               = "alphabridge-transaction-events-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "handler" {
  statement {
    sid       = "ReadEvents"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.events.arn]
  }

  statement {
    sid       = "WriteRealtimeFiles"
    actions   = ["s3:PutObject"]
    resources = ["${data.aws_s3_bucket.gold.arn}/realtime/*"]
  }

  statement {
    sid       = "UseLakeKey"
    actions   = ["kms:GenerateDataKey", "kms:Encrypt"]
    resources = [data.aws_kms_alias.lake.target_key_arn]
  }

  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.handler.arn}:*"]
  }
}

resource "aws_iam_role_policy" "handler" {
  name   = "alphabridge-transaction-events-lambda"
  role   = aws_iam_role.handler.id
  policy = data.aws_iam_policy_document.handler.json
}
