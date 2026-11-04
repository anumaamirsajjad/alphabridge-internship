# Tests for the Silver transform. They need PySpark and Java, so they are skipped on machines
# without Java. CI installs both (see .github/workflows/deploy-api.yml, job etl-test).

import shutil
from datetime import datetime
from decimal import Decimal

import pytest

pyspark = pytest.importorskip("pyspark")

from pyspark.sql import SparkSession  # noqa: E402

from lib.silver import to_silver_transactions  # noqa: E402


@pytest.fixture(scope="module")
def spark():
    if shutil.which("java") is None:
        pytest.skip("Java is not installed; Spark tests run in CI")
    session = (
        SparkSession.builder.master("local[1]")
        .config("spark.sql.session.timeZone", "UTC")
        .getOrCreate()
    )
    yield session
    session.stop()


COLUMNS = [
    "transaction_id", "amount", "currency", "status",
    "updated_at", "version", "ingest_date",
]


def test_keeps_only_the_latest_version_of_each_transaction(spark):
    rows = [
        ("t1", "10.00", "usd", "PENDING", datetime(2026, 11, 1, 9), 1, "2026-11-01"),
        ("t1", "10.00", "usd", "completed", datetime(2026, 11, 1, 10), 2, "2026-11-01"),
        ("t1", "10.00", "usd", "completed", datetime(2026, 11, 1, 10), 2, "2026-11-02"),
        ("t2", "5.50", "PKR", "pending", datetime(2026, 11, 1, 8), 1, "2026-11-01"),
    ]
    df = spark.createDataFrame(rows, COLUMNS)

    result = to_silver_transactions(df).collect()

    by_id = {r["transaction_id"]: r for r in result}
    assert len(result) == 2
    # Same updated_at and version: the later ingest_date wins.
    assert by_id["t1"]["ingest_date"] == "2026-11-02"
    assert by_id["t1"]["status"] == "completed"


def test_casts_amount_and_normalises_codes(spark):
    rows = [("t1", "10", " usd ", " PENDING ", datetime(2026, 11, 1), 1, "2026-11-01")]
    df = spark.createDataFrame(rows, COLUMNS)

    row = to_silver_transactions(df).collect()[0]

    assert row["amount"] == Decimal("10.00")
    assert row["currency"] == "USD"
    assert row["status"] == "pending"
