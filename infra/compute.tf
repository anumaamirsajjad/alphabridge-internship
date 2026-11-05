# The app servers, in two environments: "blue" and "green" (blue/green deploys).
#
# Each environment has its own server recipe (launch template), its own group of servers (auto
# scaling group), and its own target group in alb.tf. Only the environment named in live_color
# receives traffic. The other one is the place where the next release is started and tested.
#
# The blue names are the ones that already exist (we created them by hand), so they're imported
# or moved, not recreated. See README.md.

locals {
  # The settings that differ between the two environments. Everything else is shared.
  environments = {
    blue = {
      image_tag = var.blue_image_tag
      capacity  = var.blue_capacity
      lt_name   = "alphabridge-app-lt"
      asg_name  = "alphabridge-asg"
      tg_name   = "alphabridge-tg"
    }
    green = {
      image_tag = var.green_image_tag
      capacity  = var.green_capacity
      lt_name   = "alphabridge-app-lt-green"
      asg_name  = "alphabridge-asg-green"
      tg_name   = "alphabridge-tg-green"
    }
  }

  # The environment that does not take traffic. The next release goes here.
  candidate_color = var.live_color == "blue" ? "green" : "blue"
}

# The latest Amazon Linux 2023 image. It's looked up each time, so a new image can't go unnoticed.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_launch_template" "color" {
  for_each = local.environments

  name          = each.value.lt_name
  image_id      = data.aws_ami.al2023.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.app_server.name
  }

  # Each server gets a public address, so it can reach ECR and Secrets Manager.
  # Its firewall is the app group, which only accepts traffic from the load balancer.
  network_interfaces {
    device_index                = 0
    associate_public_ip_address = true
    security_groups             = [aws_security_group.app.id]
  }

  # events_env is empty while events are off, so the startup script stays exactly as it was.
  user_data = base64encode(templatefile("${path.module}/templates/app-user-data.sh.tftpl", {
    region     = var.region
    registry   = "${var.account_id}.dkr.ecr.${var.region}.amazonaws.com"
    image_tag  = each.value.image_tag
    log_group  = aws_cloudwatch_log_group.app.name
    events_env = var.events_enabled ? "-e EVENTS_QUEUE_URL=${data.aws_sqs_queue.events[0].url} " : ""
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "alphabridge-app"
    }
  }
}

resource "aws_autoscaling_group" "color" {
  for_each = local.environments

  name = each.value.asg_name

  # min and desired follow the environment's capacity. 0 means the environment is switched off.
  min_size            = each.value.capacity
  desired_capacity    = each.value.capacity
  max_size            = var.app_server_max
  vpc_zone_identifier = data.aws_subnets.default.ids

  # Points at the newest recipe version of this environment. A new image tag changes the recipe,
  # which starts a refresh of this environment only. The live environment is changed only when its
  # own tag changes, so a release on the idle environment never touches the live servers.
  launch_template {
    id      = aws_launch_template.color[each.key].id
    version = aws_launch_template.color[each.key].latest_version
  }

  # Replaces the servers one at a time. At least half stay in service, and each new server gets
  # 120 seconds to start before the next one is replaced. This is what keeps a deploy from dropping requests.
  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 120
    }
  }

  # The load balancer decides a server is healthy, and replaces it if it isn't.
  target_group_arns         = [aws_lb_target_group.color[each.key].arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  # The scaling policy in scaling.tf changes desired_capacity at runtime. Without this, every
  # terraform apply would reset it. min_size stays under Terraform control (the environment's capacity).
  lifecycle {
    ignore_changes = [desired_capacity]
  }

  tag {
    key                 = "Name"
    value               = "alphabridge-app"
    propagate_at_launch = true
  }

  # Which environment a server belongs to, so the blue and green servers can be told apart in the console.
  tag {
    key                 = "Environment"
    value               = each.key
    propagate_at_launch = true
  }
}

# The blue environment was created by hand before the blue/green setup, under these names.
# These moves keep the existing resources, so Terraform does not destroy and recreate the live servers.
moved {
  from = aws_launch_template.app
  to   = aws_launch_template.color["blue"]
}

moved {
  from = aws_autoscaling_group.app
  to   = aws_autoscaling_group.color["blue"]
}
