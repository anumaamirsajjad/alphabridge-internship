# The daily pipeline: a schedule starts a Step Functions run, which
#   1. copies each table to Bronze (up to 2 at a time),
#   2. builds Silver transactions from Bronze,
#   3. builds Silver accounts, refunds, and cancellations from Bronze,
#   4. builds the Gold tables from Silver.
# If any step fails, the run stops and an alarm is raised.

resource "aws_cloudwatch_log_group" "pipeline" {
  name              = "/aws/vendedlogs/states/alphabridge-etl-pipeline"
  retention_in_days = 30
}

resource "aws_sfn_state_machine" "pipeline" {
  name     = "alphabridge-etl-pipeline"
  role_arn = aws_iam_role.pipeline.arn

  definition = jsonencode({
    Comment = "Daily copy of the source tables to Bronze, then Silver, then Gold"
    StartAt = "CopyTablesToBronze"
    States = {
      CopyTablesToBronze = {
        Type           = "Map"
        ItemsPath      = "$.tables"
        MaxConcurrency = 2
        Parameters = {
          "table.$" = "$$.Map.Item.Value"
          "since.$" = "$.since"
        }
        ItemProcessor = {
          ProcessorConfig = { Mode = "INLINE" }
          StartAt         = "BronzeJob"
          States = {
            BronzeJob = {
              Type     = "Task"
              Resource = "arn:aws:states:::glue:startJobRun.sync"
              Parameters = {
                JobName = aws_glue_job.bronze.name
                Arguments = {
                  "--table.$"     = "$.table"
                  "--since.$"     = "$.since"
                  "--jdbc_url"    = local.jdbc_url
                  "--secret_id"   = var.etl_db_secret_name
                  "--bronze_path" = local.bronze_s3
                }
              }
              End = true
            }
          }
        }
        Next = "BuildSilverTransactions"
      }

      BuildSilverTransactions = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = aws_glue_job.silver.name
        }
        Next = "BuildSilverTables"
      }

      BuildSilverTables = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = aws_glue_job.silver_tables.name
        }
        Next = "BuildGold"
      }

      BuildGold = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = aws_glue_job.gold.name
        }
        End = true
      }
    }
  })

  logging_configuration {
    include_execution_data = false
    level                  = "ERROR"
    log_destination        = "${aws_cloudwatch_log_group.pipeline.arn}:*"
  }
}

# The schedule. The "since" value is the epoch, so each run reads whole tables. Incremental
# runs need a watermark store, which is a Phase 2 item in etl/TODO.md.
resource "aws_cloudwatch_event_rule" "daily" {
  name                = "alphabridge-etl-daily"
  description         = "Starts the ETL pipeline each day"
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "daily" {
  rule     = aws_cloudwatch_event_rule.daily.name
  arn      = aws_sfn_state_machine.pipeline.arn
  role_arn = aws_iam_role.scheduler.arn

  input = jsonencode({
    tables = var.tables
    since  = "1970-01-01T00:00:00+00:00"
  })
}

resource "aws_sns_topic" "alerts" {
  name = "alphabridge-etl-alerts"
}

resource "aws_cloudwatch_metric_alarm" "pipeline_failed" {
  alarm_name          = "alphabridge-etl-pipeline-failed"
  alarm_description   = "The ETL pipeline run failed"
  namespace           = "AWS/States"
  metric_name         = "ExecutionsFailed"
  dimensions          = { StateMachineArn = aws_sfn_state_machine.pipeline.arn }
  statistic           = "Sum"
  period              = 86400
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
