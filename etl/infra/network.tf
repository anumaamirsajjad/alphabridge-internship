# Network for the Glue jobs. The jobs run in the same default VPC as the database, so they can
# reach it on port 5432. Nothing here changes the API's network.
#
# The database's security group (infra/security.tf) allows port 5432 from this group once
# etl_access_enabled is set to true in the API stack. Apply this ETL stack first, then turn that
# flag on in the API stack. The flag defaults to off, so the API deploy is unchanged until then.
#
# Glue workers have no internet route, so they reach S3 and Secrets Manager through VPC endpoints:
#   - S3 gateway endpoint: free. It adds one route to the default VPC's main route table.
#   - Secrets Manager interface endpoint: a small monthly charge (one subnet only, here).
#     It uses private DNS, which applies to the whole VPC, so the API servers reach Secrets
#     Manager through it too. The endpoint's security group therefore allows the whole VPC on 443.
#
# NOT COVERED YET: Glue writes job logs to CloudWatch Logs. That needs a logs endpoint or NAT
# too. Check the first run's logs; add an endpoint only if it fails.

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_route_table" "main" {
  vpc_id = data.aws_vpc.default.id

  filter {
    name   = "association.main"
    values = ["true"]
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = data.aws_vpc.default.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [data.aws_route_table.main.id]
}

resource "aws_security_group" "secrets_endpoint" {
  name        = "alphabridge-etl-secrets-endpoint-sg"
  description = "Secrets Manager endpoint: HTTPS from inside the VPC"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTPS from the VPC (Glue workers and API servers)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }
}

resource "aws_vpc_endpoint" "secrets_manager" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [tolist(data.aws_subnets.default.ids)[0]]
  security_group_ids  = [aws_security_group.secrets_endpoint.id]
  private_dns_enabled = true
}

resource "aws_security_group" "glue" {
  name        = "alphabridge-etl-glue-sg"
  description = "Glue ETL workers: talk to each other, and out to the database"
  vpc_id      = data.aws_vpc.default.id

  # Glue workers must reach each other on any port during a job run.
  ingress {
    description = "Workers of the same job"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Glue requires an outbound rule that allows all ports. Terraform removes AWS's default
  # outbound rule when none is written, so it is listed here.
  egress {
    description = "All outbound (database, S3, Secrets Manager, endpoints)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_subnet" "glue" {
  id = tolist(data.aws_subnets.default.ids)[0]
}

resource "aws_glue_connection" "vpc" {
  name            = "alphabridge-etl-vpc"
  connection_type = "NETWORK"

  physical_connection_requirements {
    availability_zone      = data.aws_subnet.glue.availability_zone
    security_group_id_list = [aws_security_group.glue.id]
    subnet_id              = data.aws_subnet.glue.id
  }
}
