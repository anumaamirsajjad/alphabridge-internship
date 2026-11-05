# SRE alerting: SLI alarms and an SLO burn alert.
#
# SLOs (starting values, to be confirmed by the business):
#   - Availability: 99.9% of API requests are not 5xx, over 30 days.
#       Error budget = 0.1%. Fast-burn threshold = 14.4 x 0.1% = 1.44% errors.
#   - Latency: p95 of target response time under 300 ms.
#   - Event freshness: the oldest transfer event waits in SQS under 5 minutes.
#
# Every alarm notifies the SRE topic below. The topic has no subscribers yet, so nothing is sent
# until one is added. Email is out of scope for now. The existing ETL and DLQ alarms are not changed here.

resource "aws_sns_topic" "sre_alerts" {
  name = "alphabridge-sre-alerts"
}

# SLI: availability, with a fast-burn threshold. Fires when more than 1.44% of requests are 5xx
# for 3 consecutive 5-minute periods (15 minutes).
resource "aws_cloudwatch_metric_alarm" "api_availability_fast_burn" {
  alarm_name          = "alphabridge-api-availability-fast-burn"
  alarm_description   = "API 5xx rate above 1.44%: the 99.9% monthly error budget is burning 14.4 times too fast."
  comparison_operator = "GreaterThanThreshold"
  threshold           = 1.44
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.sre_alerts.arn]
  ok_actions          = [aws_sns_topic.sre_alerts.arn]

  metric_query {
    id          = "errors"
    return_data = false
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      dimensions  = { LoadBalancer = aws_lb.api.arn_suffix }
      period      = 300
      stat        = "Sum"
    }
  }

  metric_query {
    id          = "requests"
    return_data = false
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      dimensions  = { LoadBalancer = aws_lb.api.arn_suffix }
      period      = 300
      stat        = "Sum"
    }
  }

  metric_query {
    id          = "error_pct"
    expression  = "IF(requests > 0, 100 * errors / requests, 0)"
    label       = "5xx percent"
    return_data = true
  }
}

# SLI: latency. p95 of target response time must stay under 0.3 s for 15 minutes.
resource "aws_cloudwatch_metric_alarm" "api_latency_p95" {
  alarm_name          = "alphabridge-api-latency-p95"
  alarm_description   = "API p95 response time above 300 ms"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = { LoadBalancer = aws_lb.api.arn_suffix }
  extended_statistic  = "p95"
  period              = 300
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 0.3
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.sre_alerts.arn]
  ok_actions          = [aws_sns_topic.sre_alerts.arn]
}

# SLI: event freshness. The oldest transfer event in the queue must not wait longer than 5 minutes.
# The queue lives in the realtime stack, so it is referenced by name, not by resource.
resource "aws_cloudwatch_metric_alarm" "events_freshness" {
  alarm_name          = "alphabridge-events-freshness"
  alarm_description   = "Transfer events have waited in the queue longer than 5 minutes"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  dimensions          = { QueueName = var.events_queue_name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 300
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.sre_alerts.arn]
  ok_actions          = [aws_sns_topic.sre_alerts.arn]
}
