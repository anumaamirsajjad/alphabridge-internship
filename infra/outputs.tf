# Values other tools need. The load test and the pipeline read these, so no URL is typed by hand.

output "api_url" {
  description = "The public address of the API, through the gateway. Use this for the load test."
  value       = aws_api_gateway_stage.prod.invoke_url
}

output "load_balancer_dns" {
  description = "The load balancer's address, for checking the app directly."
  value       = aws_lb.api.dns_name
}

output "live_color" {
  description = "The environment serving customer traffic right now."
  value       = var.live_color
}

output "candidate_color" {
  description = "The idle environment, where the next release goes and is tested before cutover."
  value       = local.candidate_color
}

output "auto_scaling_groups" {
  description = "The auto scaling group of each environment, for the instance checks in the runbook."
  value       = { for k, asg in aws_autoscaling_group.color : k => asg.name }
}
