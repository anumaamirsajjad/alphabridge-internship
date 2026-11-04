# What this file does:
#   Glue job. Builds the Gold tables (dim_account, fact_transactions,
#   agg_daily_transaction_summary) from the Silver layer, and writes them to the Gold bucket.
#   Each run rebuilds the Gold tables from scratch.
#
# Arguments (set by Step Functions):
#   --silver_path  s3://<silver-bucket>/<prefix>
#   --gold_path    s3://<gold-bucket>/<prefix>

import sys

from awsglue.context import GlueContext
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext

from lib.gold import build_daily_summary, build_dim_account, build_fact_transactions

args = getResolvedOptions(sys.argv, ["JOB_NAME", "silver_path", "gold_path"])

spark = GlueContext(SparkContext()).spark_session
spark.conf.set("spark.sql.session.timeZone", "UTC")

silver = args["silver_path"].rstrip("/")
gold = args["gold_path"].rstrip("/")

accounts = spark.read.parquet(f"{silver}/accounts/")
transactions = spark.read.parquet(f"{silver}/transactions/")

outputs = {
    "dim_account": build_dim_account(accounts),
    "fact_transactions": build_fact_transactions(transactions),
}
outputs["agg_daily_transaction_summary"] = build_daily_summary(outputs["fact_transactions"])

for name, df in outputs.items():
    df.write.mode("overwrite").parquet(f"{gold}/{name}/")
    print(f"gold {name}: {df.count()} rows")
