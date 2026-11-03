# The three firewalls, from the outside in: the load balancer, the app servers, and the database.
#
# Each group lists every inbound rule it should have. Terraform removes any other inbound rule,
# so the old rules are cleaned up on the next apply. Outbound rules are not listed, so the
# default "allow all outbound" stays as it is.
#
# These groups already exist (we created them by hand). They're imported, not recreated, and
# the descriptions must match the existing ones exactly, or Terraform would recreate them.

# The load balancer accepts web traffic from anywhere on port 80.
resource "aws_security_group" "alb" {
  name        = "alb-sg"
  description = "Load balancer: web traffic on port 80"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Web traffic from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# The app servers accept port 8000 from the load balancer only.
resource "aws_security_group" "app" {
  name        = "ec2-sg"
  description = "App servers: port 8000 from the load balancer only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "App port from the load balancer"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
}

# The ETL Glue workers' security group. It lives in the ETL stack (etl/infra), so it is looked
# up by name. Only read when etl_access_enabled is true.
data "aws_security_group" "etl_glue" {
  count  = var.etl_access_enabled ? 1 : 0
  name   = "alphabridge-etl-glue-sg"
  vpc_id = data.aws_vpc.default.id
}

# The database accepts PostgreSQL (port 5432) from the app servers, and from the ETL workers
# when etl_access_enabled is on.
resource "aws_security_group" "db" {
  name        = "alphabridge-pg-sg"
  description = "Created by RDS management console"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "PostgreSQL from the app servers"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  dynamic "ingress" {
    for_each = var.etl_access_enabled ? [1] : []

    content {
      description     = "PostgreSQL from the ETL Glue workers"
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [data.aws_security_group.etl_glue[0].id]
    }
  }
}
