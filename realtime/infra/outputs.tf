# Values the API and the Lambda need. Run "terraform output" to read them.

output "events_queue_url" {
  value = aws_sqs_queue.events.url
}

output "events_queue_arn" {
  value = aws_sqs_queue.events.arn
}

output "dead_letter_queue_arn" {
  value = aws_sqs_queue.dead_letter.arn
}
