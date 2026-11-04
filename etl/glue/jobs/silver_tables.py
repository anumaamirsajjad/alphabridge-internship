# What this file does:
#   Glue job. Builds the Silver tables accounts, refunds, and cancellations from their Bronze copies.
#   Each run rebuilds the whole Silver table. That is simple, and fine at the current sizes.
#
# Arguments (set by Step Functions):
#   --bronze_path  s3://<bronze-bucket>/<prefix>
#   --silver_path  s3://<silver-bucket>/<prefix>

import sys

from awsglue.context import GlueContext
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext

from lib.silver import to_silver_accounts, to_silver_cancellations, to_silver_refunds

args = getResolvedOptions(sys.argv, ["JOB_NAME", "bronze_path", "silver_path"])

spark = GlueContext(SparkContext()).spark_session
spark.conf.set("spark.sql.session.timeZone", "UTC")

bronze = args["bronze_path"].rstrip("/")
silver = args["silver_path"].rstrip("/")

TABLES = {
    "accounts": to_silver_accounts,
    "refunds": to_silver_refunds,
    "cancellations": to_silver_cancellations,
}

for table, transform in TABLES.items():
    raw = spark.read.parquet(f"{bronze}/{table}/")
    clean = transform(raw)
    clean.write.mode("overwrite").parquet(f"{silver}/{table}/")
    print(f"silver {table}: {raw.count()} bronze rows -> {clean.count()} silver rows")
