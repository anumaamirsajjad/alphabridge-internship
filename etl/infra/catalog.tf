# Athena can query the Silver and Gold data only after the Glue Data Catalog knows each table.
# The table definitions below match the Parquet files the Silver and Gold jobs write.
#
# The schemas are fixed here on purpose. A crawler would guess the types from the data, and a
# guess that changes (for example, a column becomes a number) would break reports silently.
# If a Silver or Gold job changes its columns, change the matching entry here as well.

locals {
  silver_s3_base = "s3://${aws_s3_bucket.lake["silver"].bucket}"
  gold_s3_base   = "s3://${aws_s3_bucket.lake["gold"].bucket}"

  catalog_tables = {
    silver_transactions = {
      location = "${local.silver_s3_base}/transactions/"
      columns = [
        { name = "transaction_id", type = "string" },
        { name = "from_account_id", type = "string" },
        { name = "to_account_id", type = "string" },
        { name = "amount", type = "decimal(15,2)" },
        { name = "currency", type = "string" },
        { name = "description", type = "string" },
        { name = "status", type = "string" },
        { name = "created_at", type = "timestamp" },
        { name = "updated_at", type = "timestamp" },
        { name = "version", type = "int" },
        { name = "ingest_date", type = "date" },
      ]
    }

    silver_accounts = {
      location = "${local.silver_s3_base}/accounts/"
      columns = [
        { name = "account_id", type = "string" },
        { name = "account_holder", type = "string" },
        { name = "currency", type = "string" },
        { name = "balance", type = "decimal(15,2)" },
        { name = "created_at", type = "timestamp" },
        { name = "ingest_date", type = "date" },
      ]
    }

    silver_refunds = {
      location = "${local.silver_s3_base}/refunds/"
      columns = [
        { name = "refund_id", type = "string" },
        { name = "transaction_id", type = "string" },
        { name = "amount", type = "decimal(15,2)" },
        { name = "reason", type = "string" },
        { name = "status", type = "string" },
        { name = "created_at", type = "timestamp" },
        { name = "ingest_date", type = "date" },
      ]
    }

    silver_cancellations = {
      location = "${local.silver_s3_base}/cancellations/"
      columns = [
        { name = "cancellation_id", type = "string" },
        { name = "transaction_id", type = "string" },
        { name = "reason", type = "string" },
        { name = "status", type = "string" },
        { name = "created_at", type = "timestamp" },
        { name = "ingest_date", type = "date" },
      ]
    }

    gold_dim_account = {
      location = "${local.gold_s3_base}/dim_account/"
      columns = [
        { name = "account_id", type = "string" },
        { name = "currency", type = "string" },
        { name = "created_at", type = "timestamp" },
      ]
    }

    gold_fact_transactions = {
      location = "${local.gold_s3_base}/fact_transactions/"
      columns = [
        { name = "transaction_id", type = "string" },
        { name = "from_account_id", type = "string" },
        { name = "to_account_id", type = "string" },
        { name = "amount", type = "decimal(15,2)" },
        { name = "currency", type = "string" },
        { name = "status", type = "string" },
        { name = "created_at", type = "timestamp" },
        { name = "transaction_date", type = "date" },
      ]
    }

    gold_agg_daily_transaction_summary = {
      location = "${local.gold_s3_base}/agg_daily_transaction_summary/"
      columns = [
        { name = "transaction_date", type = "date" },
        { name = "status", type = "string" },
        { name = "transaction_count", type = "bigint" },
        { name = "total_amount", type = "decimal(18,2)" },
      ]
    }
  }
}

resource "aws_glue_catalog_table" "lake" {
  for_each = local.catalog_tables

  name          = each.key
  database_name = aws_glue_catalog_database.lake.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    classification = "parquet"
    EXTERNAL       = "TRUE"
  }

  storage_descriptor {
    location      = each.value.location
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    dynamic "columns" {
      for_each = each.value.columns

      content {
        name = columns.value.name
        type = columns.value.type
      }
    }
  }
}

# The workgroup Athena queries run in. Results go to the Athena results bucket, encrypted with the
# lake key, and they expire after 7 days (see storage.tf).
resource "aws_athena_workgroup" "lake" {
  name          = "alphabridge-etl"
  force_destroy = false

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.lake["athena"].bucket}/results/"

      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn       = aws_kms_key.lake.arn
      }
    }
  }
}
