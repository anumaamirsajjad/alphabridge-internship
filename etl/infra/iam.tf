# Who may do what in the ETL pipeline. Each role gets only the permissions its service needs.
#
#   glue_job       reads the source database, reads the scripts, writes the three data layers
#   pipeline       starts Glue jobs and waits for them (Step Functions)
#   scheduler      starts the pipeline on schedule (EventBridge)
#
# None of these roles can touch the API's resources.

data "aws_secretsmanager_secret" "etl_db" {
  name = var.etl_db_secret_name
}

data "aws_iam_policy_document" "glue_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue_job" {
  name               = "alphabridge-etl-glue"
  assume_role_policy = data.aws_iam_policy_document.glue_assume.json
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_job.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

data "aws_iam_policy_document" "glue_job" {
  statement {
    sid       = "ReadSourceCredentials"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [data.aws_secretsmanager_secret.etl_db.arn]
  }

  statement {
    sid       = "ReadScripts"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.lake["scripts"].arn}/*"]
  }

  statement {
    sid     = "ReadWriteLayers"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.lake["bronze"].arn,
      "${aws_s3_bucket.lake["bronze"].arn}/*",
      aws_s3_bucket.lake["silver"].arn,
      "${aws_s3_bucket.lake["silver"].arn}/*",
      aws_s3_bucket.lake["gold"].arn,
      "${aws_s3_bucket.lake["gold"].arn}/*",
    ]
  }

  statement {
    sid       = "UseLakeKey"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.lake.arn]
  }
}

resource "aws_iam_role_policy" "glue_job" {
  name   = "alphabridge-etl-glue"
  role   = aws_iam_role.glue_job.id
  policy = data.aws_iam_policy_document.glue_job.json
}

data "aws_iam_policy_document" "sfn_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pipeline" {
  name               = "alphabridge-etl-pipeline"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume.json
}

data "aws_iam_policy_document" "pipeline" {
  # Start the Glue jobs and wait for them to finish (the ".sync" integration).
  statement {
    sid = "RunGlueJobs"
    actions = [
      "glue:StartJobRun",
      "glue:GetJobRun",
      "glue:GetJobRuns",
      "glue:BatchStopJobRun",
    ]
    resources = [
      "arn:aws:glue:${var.region}:${var.account_id}:job/alphabridge-etl-*",
    ]
  }

  # Step Functions uses an EventBridge rule to learn when a Glue job ends.
  statement {
    sid = "WatchGlueJobs"
    actions = [
      "events:PutRule",
      "events:PutTargets",
      "events:DescribeRule",
    ]
    resources = ["arn:aws:events:${var.region}:${var.account_id}:rule/StepFunctionsGetEventsForGlueJobRunRule"]
  }

  statement {
    sid = "WriteLogs"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "pipeline" {
  name   = "alphabridge-etl-pipeline"
  role   = aws_iam_role.pipeline.id
  policy = data.aws_iam_policy_document.pipeline.json
}

data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "alphabridge-etl-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

data "aws_iam_policy_document" "scheduler" {
  statement {
    sid       = "StartPipeline"
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.pipeline.arn]
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name   = "alphabridge-etl-scheduler"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler.json
}
