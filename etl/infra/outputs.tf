# Values other steps need. Run "terraform output" to read them.

output "bronze_bucket" {
  value = aws_s3_bucket.lake["bronze"].id
}

output "silver_bucket" {
  value = aws_s3_bucket.lake["silver"].id
}

output "gold_bucket" {
  value = aws_s3_bucket.lake["gold"].id
}

output "athena_results_bucket" {
  value = aws_s3_bucket.lake["athena"].id
}

output "pipeline_state_machine_arn" {
  value = aws_sfn_state_machine.pipeline.arn
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}
