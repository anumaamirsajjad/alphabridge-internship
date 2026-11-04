# What this file does:
#   Glue job. Reads every Bronze partition of transactions, keeps the latest version of each
#   transaction, and writes the result to the Silver layer.
#
#   This is a full rebuild on each run. That is fine while the table is small. Once it grows,
#   switch to an incremental merge (see etl/TODO.md, Phase 2).
#
# Arguments (set by Step Functions):
#   --bronze_path  s3://<bronze-bucket>/<prefix>
#   --silver_path  s3://<silver-bucket>/<prefix>

import sys

from awsglue.context import GlueContext
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext

from lib.silver import to_silver_transactions

args = getResolvedOptions(sys.argv, ["JOB_NAME", "bronze_path", "silver_path"])

spark = GlueContext(SparkContext()).spark_session
spark.conf.set("spark.sql.session.timeZone", "UTC")

bronze = spark.read.parquet(f"{args['bronze_path'].rstrip('/')}/transactions/")
silver = to_silver_transactions(bronze)

(
    silver.write.mode("overwrite")
    .parquet(f"{args['silver_path'].rstrip('/')}/transactions/")
)

print(f"silver transactions: {bronze.count()} bronze rows -> {silver.count()} silver rows")
