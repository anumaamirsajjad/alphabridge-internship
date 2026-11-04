# What this file does:
#   Runs data checks on the lake through Athena, and prints PASS or FAIL for each one.
#   Each check is one SQL query that returns a single number. For "must be zero" checks the
#   number is the count of bad rows. For "must match" checks it is the difference between two totals.
#
#   Run from the etl folder, with AWS credentials that can use the alphabridge-etl workgroup:
#     python tests/athena_checks.py
#
#   Exit code 0 means every check passed. Any failure exits with 1.

import json
import subprocess
import sys
import time

WORKGROUP = "alphabridge-etl"
DATABASE = "alphabridge_lake"
REGION = "ap-south-1"

VALID_TX_STATUSES = "('pending','completed','failed','cancelled','refunded')"
VALID_REFUND_STATUSES = "('pending','processed','rejected')"
VALID_CANCELLATION_STATUSES = "('pending','completed','rejected')"

# (name, SQL returning one number, expected value)
CHECKS = [
    # Duplicates: every key must appear once.
    ("no duplicate transactions (silver)",
     "SELECT count(*) - count(DISTINCT transaction_id) FROM silver_transactions", 0),
    ("no duplicate accounts (silver)",
     "SELECT count(*) - count(DISTINCT account_id) FROM silver_accounts", 0),
    ("no duplicate refunds (silver)",
     "SELECT count(*) - count(DISTINCT refund_id) FROM silver_refunds", 0),
    ("no duplicate cancellations (silver)",
     "SELECT count(*) - count(DISTINCT cancellation_id) FROM silver_cancellations", 0),
    ("no duplicate transactions (gold fact)",
     "SELECT count(*) - count(DISTINCT transaction_id) FROM gold_fact_transactions", 0),
    ("no duplicate accounts (gold dim)",
     "SELECT count(*) - count(DISTINCT account_id) FROM gold_dim_account", 0),

    # Keys and values make sense.
    ("no empty keys or amounts in transactions",
     "SELECT count(*) FROM silver_transactions WHERE transaction_id IS NULL OR from_account_id IS NULL "
     "OR to_account_id IS NULL OR amount IS NULL", 0),
    ("every transaction amount is above zero",
     "SELECT count(*) FROM silver_transactions WHERE amount <= 0", 0),
    ("no transfer sends money to the same account",
     "SELECT count(*) FROM silver_transactions WHERE from_account_id = to_account_id", 0),
    ("every currency is 3 capital letters (transactions)",
     "SELECT count(*) FROM silver_transactions WHERE NOT regexp_like(currency, '^[A-Z]{3}$')", 0),
    ("every transaction status is a known value",
     f"SELECT count(*) FROM silver_transactions WHERE status NOT IN {VALID_TX_STATUSES}", 0),
    ("every refund status is a known value",
     f"SELECT count(*) FROM silver_refunds WHERE status NOT IN {VALID_REFUND_STATUSES}", 0),
    ("every cancellation status is a known value",
     f"SELECT count(*) FROM silver_cancellations WHERE status NOT IN {VALID_CANCELLATION_STATUSES}", 0),

    # Links between tables make sense.
    ("every transaction account exists in the account list",
     "SELECT count(*) FROM gold_fact_transactions f WHERE "
     "f.from_account_id NOT IN (SELECT account_id FROM gold_dim_account) "
     "OR f.to_account_id NOT IN (SELECT account_id FROM gold_dim_account)", 0),
    ("every refund points to a real transaction",
     "SELECT count(*) FROM silver_refunds r WHERE r.transaction_id NOT IN "
     "(SELECT transaction_id FROM silver_transactions)", 0),
    ("every cancellation points to a real transaction",
     "SELECT count(*) FROM silver_cancellations c WHERE c.transaction_id NOT IN "
     "(SELECT transaction_id FROM silver_transactions)", 0),

    # Each layer agrees with the one before it.
    ("silver transactions count equals gold fact count",
     "SELECT (SELECT count(*) FROM silver_transactions) - (SELECT count(*) FROM gold_fact_transactions)", 0),
    ("silver transactions total equals gold fact total",
     "SELECT round((SELECT sum(amount) FROM silver_transactions) - (SELECT sum(amount) FROM gold_fact_transactions), 2)", 0),
    ("daily summary counts add up to the fact count",
     "SELECT (SELECT sum(transaction_count) FROM gold_agg_daily_transaction_summary) - "
     "(SELECT count(*) FROM gold_fact_transactions)", 0),
    ("daily summary totals add up to the fact total",
     "SELECT round((SELECT sum(total_amount) FROM gold_agg_daily_transaction_summary) - "
     "(SELECT sum(amount) FROM gold_fact_transactions), 2)", 0),
    ("gold accounts count equals silver accounts count",
     "SELECT (SELECT count(*) FROM gold_dim_account) - (SELECT count(*) FROM silver_accounts)", 0),

    # Business views return the same rows as their Gold tables.
    ("view v_transactions matches gold fact",
     "SELECT (SELECT count(*) FROM v_transactions) - (SELECT count(*) FROM gold_fact_transactions)", 0),
    ("view v_daily_transaction_summary matches gold summary",
     "SELECT (SELECT count(*) FROM v_daily_transaction_summary) - "
     "(SELECT count(*) FROM gold_agg_daily_transaction_summary)", 0),
    ("view v_accounts matches gold accounts",
     "SELECT (SELECT count(*) FROM v_accounts) - (SELECT count(*) FROM gold_dim_account)", 0),
]


def run_query(sql):
    """Run one Athena query and return its single result value as text."""
    start = subprocess.run(
        ["aws", "athena", "start-query-execution", "--work-group", WORKGROUP,
         "--query-execution-context", f"Database={DATABASE}", "--query-string", sql,
         "--region", REGION, "--query", "QueryExecutionId", "--output", "text"],
        capture_output=True, text=True, check=True,
    )
    query_id = start.stdout.strip()

    for _ in range(120):
        state = subprocess.run(
            ["aws", "athena", "get-query-execution", "--query-execution-id", query_id,
             "--region", REGION, "--query", "QueryExecution.Status.State", "--output", "text"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        if state == "SUCCEEDED":
            break
        if state in ("FAILED", "CANCELLED"):
            reason = subprocess.run(
                ["aws", "athena", "get-query-execution", "--query-execution-id", query_id,
                 "--region", REGION, "--query", "QueryExecution.Status.StateChangeReason", "--output", "text"],
                capture_output=True, text=True,
            ).stdout.strip()
            raise RuntimeError(f"query {state}: {reason}")
        time.sleep(2)
    else:
        raise RuntimeError("query did not finish in time")

    result = subprocess.run(
        ["aws", "athena", "get-query-results", "--query-execution-id", query_id,
         "--region", REGION, "--output", "json"],
        capture_output=True, text=True, check=True,
    )
    rows = json.loads(result.stdout)["ResultSet"]["Rows"]
    return rows[1]["Data"][0]["VarCharValue"]


def main():
    failures = 0
    for name, sql, expected in CHECKS:
        try:
            value = run_query(sql)
            ok = float(value) == float(expected)
            status = "PASS" if ok else "FAIL"
            detail = f"value {value}"
        except Exception as error:  # report the error and keep going with the other checks
            ok = False
            status = "ERROR"
            detail = str(error)
        if not ok:
            failures += 1
        print(f"{status:5}  {name}  ({detail})")

    print(f"\n{len(CHECKS) - failures} of {len(CHECKS)} checks passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
