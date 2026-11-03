# What this file does:
#   Glue job. Reads one table from the source database and writes it to the Bronze layer as
#   Parquet, in a partition named after the run date. Reruns on the same day replace that
#   day's partition, so a retry is safe.
#
# Arguments (set by Step Functions):
#   --table        one of the tables in lib/extract.py
#   --since        ISO timestamp of the last successful run; use the epoch for the first run
#   --jdbc_url     jdbc:postgresql://<host>:5432/alphabridge
#   --secret_id    Secrets Manager secret holding the read-only username and password (JSON)
#   --bronze_path  s3://<bronze-bucket>/<prefix>

import json
import sys
from datetime import datetime, timezone

import boto3
from awsglue.context import GlueContext
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as F

from lib.extract import extract_query

args = getResolvedOptions(
    sys.argv,
    ["JOB_NAME", "table", "since", "jdbc_url", "secret_id", "bronze_path"],
)

spark = GlueContext(SparkContext()).spark_session
spark.conf.set("spark.sql.session.timeZone", "UTC")
# Overwrite only the partitions this run writes, not the whole Bronze table.
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")

secret = json.loads(
    boto3.client("secretsmanager").get_secret_value(SecretId=args["secret_id"])["SecretString"]
)
since = datetime.fromisoformat(args["since"]).astimezone(timezone.utc)

df = (
    spark.read.format("jdbc")
    .option("url", args["jdbc_url"])
    .option("driver", "org.postgresql.Driver")
    .option("user", secret["username"])
    .option("password", secret["password"])
    .option("dbtable", extract_query(args["table"], since))
    .load()
)

run_date = datetime.now(timezone.utc).date().isoformat()
(
    df.withColumn("ingest_date", F.lit(run_date))
    .write.mode("overwrite")
    .partitionBy("ingest_date")
    .parquet(f"{args['bronze_path'].rstrip('/')}/{args['table']}/")
)

print(f"bronze {args['table']}: {df.count()} rows written for {run_date}")
