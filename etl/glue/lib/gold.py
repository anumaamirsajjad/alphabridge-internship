# What this file does:
#   Builds the Gold tables from the Silver tables. Gold is what reports and dashboards read.
#
#   Gold tables:
#     dim_account                    one row per account, without personal data
#     fact_transactions              one row per transaction, with its account keys and date
#     agg_daily_transaction_summary  count and total amount per day and status
#
#   account_holder (the name) is left out on purpose. It is personal data, and Gold is for reporting.

from pyspark.sql import functions as F


def build_dim_account(accounts):
    """One row per account, with no personal data (no account_holder)."""
    return accounts.select(
        F.col("account_id"),
        F.col("currency"),
        F.col("created_at"),
    )


def build_fact_transactions(transactions):
    """One row per transaction. transaction_date is the UTC date of creation."""
    return transactions.select(
        F.col("transaction_id"),
        F.col("from_account_id"),
        F.col("to_account_id"),
        F.col("amount"),
        F.col("currency"),
        F.col("status"),
        F.col("created_at"),
        F.to_date(F.col("created_at")).alias("transaction_date"),
    )


def build_daily_summary(fact):
    """Count and total amount per transaction_date and status.

    Uses each transaction's current status (the Silver row is the latest version).
    """
    return (
        fact.groupBy("transaction_date", "status")
        .agg(
            F.count("transaction_id").alias("transaction_count"),
            F.sum("amount").cast("decimal(18,2)").alias("total_amount"),
        )
    )
