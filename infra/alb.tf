# The load balancer: the single public entry point for the API.
#
#   Listener (port 80) -> target group of the LIVE environment (port 8000, checked at /docs)
#
# There is one target group per environment (blue and green). The listener's default action
# decides which one customers reach: it follows live_color. Changing live_color is the cutover.
#
# The load balancer and the blue target group already exist (we created them by hand), so they're
# imported or moved. See README.md.

resource "aws_lb" "api" {
  name               = "alphabridge-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "color" {
  for_each = local.environments

  name        = each.value.tg_name
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "instance"

  # Keeps the old server in service this long after it's removed, so in-flight requests finish.
  # This prevents 502 errors during a deploy.
  deregistration_delay = 60

  health_check {
    path                = "/docs"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"

  # All customer traffic goes to the live environment. Changing live_color switches it.
  default_action {
    type = "forward"

    forward {
      target_group {
        arn    = aws_lb_target_group.color[var.live_color].arn
        weight = 1
      }

      stickiness {
        enabled  = false
        duration = 3600
      }
    }
  }
}

# Optional test route. A request with the header X-Deploy-Test set to the secret value goes to the
# idle environment, so a release can be checked on the real load balancer before the cutover.
# Ordinary requests never carry this header, so they always reach the live environment.
resource "aws_lb_listener_rule" "candidate_test" {
  count = var.deploy_test_header_value == "" ? 0 : 1

  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.color[local.candidate_color].arn
  }

  condition {
    http_header {
      http_header_name = "X-Deploy-Test"
      values           = [var.deploy_test_header_value]
    }
  }
}

# The blue target group was created by hand before the blue/green setup. This move keeps it.
moved {
  from = aws_lb_target_group.app
  to   = aws_lb_target_group.color["blue"]
}
