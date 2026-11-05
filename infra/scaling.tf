# Auto scaling for the app servers (SRE).
#
# One target-tracking policy per environment (blue and green). Each policy keeps the average
# number of requests per server near var.scaling_requests_per_server. AWS creates the CloudWatch
# alarms behind the policy and adds or removes servers itself.
#
# Bounds: never below the environment's capacity (min_size in compute.tf), never above
# app_server_max. A switched-off environment (capacity 0) stays at 0 unless its capacity is raised.

resource "aws_autoscaling_policy" "requests_per_server" {
  for_each = local.environments

  name                      = "${each.value.asg_name}-requests-per-server"
  autoscaling_group_name    = aws_autoscaling_group.color[each.key].name
  policy_type               = "TargetTrackingScaling"
  estimated_instance_warmup = 120 # seconds a new server needs before it counts toward the average

  target_tracking_configuration {
    target_value = var.scaling_requests_per_server

    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      # Format required by AWS: <load balancer arn_suffix>/<target group arn_suffix>
      resource_label = "${aws_lb.api.arn_suffix}/${aws_lb_target_group.color[each.key].arn_suffix}"
    }
  }
}
