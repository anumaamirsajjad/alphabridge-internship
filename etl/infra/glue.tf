# The Glue jobs and the Data Catalog database they register tables in.
#
# One Bronze job copies any table: Step Functions passes --table on each run. One Silver job
# builds the transactions table.

locals {
  scripts_s3 = "s3://${aws_s3_bucket.lake["scripts"].id}"
  bronze_s3  = "s3://${aws_s3_bucket.lake["bronze"].id}"
  silver_s3  = "s3://${aws_s3_bucket.lake["silver"].id}"
  gold_s3    = "s3://${aws_s3_bucket.lake["gold"].id}"
  jdbc_url   = "jdbc:postgresql://${data.aws_db_instance.source.address}:${data.aws_db_instance.source.port}/${var.database_name}"

  common_job_arguments = {
    "--extra-py-files"                   = "${local.scripts_s3}/${aws_s3_object.lib.key}"
    "--job-language"                     = "python"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--TempDir"                          = "${local.scripts_s3}/tmp/"
  }
}

data "aws_db_instance" "source" {
  db_instance_identifier = var.database_identifier
}

resource "aws_glue_catalog_database" "lake" {
  name        = "alphabridge_lake"
  description = "Tables of the ETL data lake (Silver and Gold). Bronze is raw and not registered."
}

resource "aws_glue_job" "bronze" {
  name              = "alphabridge-etl-bronze"
  role_arn          = aws_iam_role.glue_job.arn
  glue_version      = var.glue_version
  worker_type       = var.glue_worker_type
  number_of_workers = var.glue_number_of_workers
  connections       = [aws_glue_connection.vpc.name]

  command {
    name            = "glueetl"
    script_location = "${local.scripts_s3}/${aws_s3_object.bronze_job.key}"
    python_version  = "3"
  }

  # Step Functions starts up to 4 table copies at once, so the job must allow 4 runs.
  execution_property {
    max_concurrent_runs = 4
  }

  default_arguments = local.common_job_arguments
}

resource "aws_glue_job" "silver" {
  name              = "alphabridge-etl-silver-transactions"
  role_arn          = aws_iam_role.glue_job.arn
  glue_version      = var.glue_version
  worker_type       = var.glue_worker_type
  number_of_workers = var.glue_number_of_workers
  connections       = [aws_glue_connection.vpc.name]

  command {
    name            = "glueetl"
    script_location = "${local.scripts_s3}/${aws_s3_object.silver_job.key}"
    python_version  = "3"
  }

  default_arguments = merge(local.common_job_arguments, {
    "--bronze_path" = local.bronze_s3
    "--silver_path" = local.silver_s3
  })
}

# Builds Silver accounts, refunds, and cancellations from Bronze.
resource "aws_glue_job" "silver_tables" {
  name              = "alphabridge-etl-silver-tables"
  role_arn          = aws_iam_role.glue_job.arn
  glue_version      = var.glue_version
  worker_type       = var.glue_worker_type
  number_of_workers = var.glue_number_of_workers
  connections       = [aws_glue_connection.vpc.name]

  command {
    name            = "glueetl"
    script_location = "${local.scripts_s3}/${aws_s3_object.silver_tables_job.key}"
    python_version  = "3"
  }

  default_arguments = merge(local.common_job_arguments, {
    "--bronze_path" = local.bronze_s3
    "--silver_path" = local.silver_s3
  })
}

# Builds the Gold tables from Silver.
resource "aws_glue_job" "gold" {
  name              = "alphabridge-etl-gold"
  role_arn          = aws_iam_role.glue_job.arn
  glue_version      = var.glue_version
  worker_type       = var.glue_worker_type
  number_of_workers = var.glue_number_of_workers
  connections       = [aws_glue_connection.vpc.name]

  command {
    name            = "glueetl"
    script_location = "${local.scripts_s3}/${aws_s3_object.gold_job.key}"
    python_version  = "3"
  }

  default_arguments = merge(local.common_job_arguments, {
    "--silver_path" = local.silver_s3
    "--gold_path"   = local.gold_s3
  })
}
