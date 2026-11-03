# The data lake: one bucket per layer, plus a bucket for Glue scripts and Athena results.
#
# Every bucket is private, versioned, and encrypted with one KMS key. Bronze is kept as raw
# history, so it moves to cheaper storage after 90 days.

resource "aws_kms_key" "lake" {
  description             = "Encrypts the ETL data lake"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "lake" {
  name          = "alias/alphabridge-etl"
  target_key_id = aws_kms_key.lake.key_id
}

locals {
  buckets = {
    bronze  = "alphabridge-lake-bronze-${var.account_id}"
    silver  = "alphabridge-lake-silver-${var.account_id}"
    gold    = "alphabridge-lake-gold-${var.account_id}"
    scripts = "alphabridge-etl-scripts-${var.account_id}"
    athena  = "alphabridge-athena-results-${var.account_id}"
  }
}

resource "aws_s3_bucket" "lake" {
  for_each = local.buckets

  bucket = each.value
}

resource "aws_s3_bucket_versioning" "lake" {
  for_each = aws_s3_bucket.lake

  bucket = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lake" {
  for_each = aws_s3_bucket.lake

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.lake.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "lake" {
  for_each = aws_s3_bucket.lake

  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bronze holds the raw copies. Old versions and old copies move to Glacier, and the
# Glue temp files are deleted after a week.
resource "aws_s3_bucket_lifecycle_configuration" "bronze" {
  bucket = aws_s3_bucket.lake["bronze"].id

  rule {
    id     = "bronze-to-glacier"
    status = "Enabled"

    filter {}

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "athena" {
  bucket = aws_s3_bucket.lake["athena"].id

  rule {
    id     = "expire-query-results"
    status = "Enabled"

    filter {}

    expiration {
      days = 7
    }
  }
}

# The Glue scripts. The lib package is zipped so the jobs can import it.
data "archive_file" "lib" {
  type        = "zip"
  output_path = "${path.module}/build/lib.zip"

  source {
    content  = file("${path.module}/../glue/lib/__init__.py")
    filename = "lib/__init__.py"
  }

  source {
    content  = file("${path.module}/../glue/lib/extract.py")
    filename = "lib/extract.py"
  }

  source {
    content  = file("${path.module}/../glue/lib/silver.py")
    filename = "lib/silver.py"
  }

  source {
    content  = file("${path.module}/../glue/lib/gold.py")
    filename = "lib/gold.py"
  }
}

resource "aws_s3_object" "lib" {
  bucket      = aws_s3_bucket.lake["scripts"].id
  key         = "lib/lib.zip"
  source      = data.archive_file.lib.output_path
  source_hash = data.archive_file.lib.output_base64sha256
  kms_key_id  = aws_kms_key.lake.arn
}

resource "aws_s3_object" "bronze_job" {
  bucket      = aws_s3_bucket.lake["scripts"].id
  key         = "jobs/bronze_extract.py"
  source      = "${path.module}/../glue/jobs/bronze_extract.py"
  source_hash = filemd5("${path.module}/../glue/jobs/bronze_extract.py")
  kms_key_id  = aws_kms_key.lake.arn
}

resource "aws_s3_object" "silver_job" {
  bucket      = aws_s3_bucket.lake["scripts"].id
  key         = "jobs/silver_transactions.py"
  source      = "${path.module}/../glue/jobs/silver_transactions.py"
  source_hash = filemd5("${path.module}/../glue/jobs/silver_transactions.py")
  kms_key_id  = aws_kms_key.lake.arn
}

resource "aws_s3_object" "silver_tables_job" {
  bucket      = aws_s3_bucket.lake["scripts"].id
  key         = "jobs/silver_tables.py"
  source      = "${path.module}/../glue/jobs/silver_tables.py"
  source_hash = filemd5("${path.module}/../glue/jobs/silver_tables.py")
  kms_key_id  = aws_kms_key.lake.arn
}

resource "aws_s3_object" "gold_job" {
  bucket      = aws_s3_bucket.lake["scripts"].id
  key         = "jobs/gold_build.py"
  source      = "${path.module}/../glue/jobs/gold_build.py"
  source_hash = filemd5("${path.module}/../glue/jobs/gold_build.py")
  kms_key_id  = aws_kms_key.lake.arn
}
