# Tests for the source query builder. Pure Python, so they run anywhere without Spark.

from datetime import datetime, timezone

import pytest

from lib.extract import OVERLAP, extract_query

SINCE = datetime(2026, 11, 1, 12, 0, tzinfo=timezone.utc)


def test_transactions_reads_from_watermark_minus_overlap():
    query = extract_query("transactions", SINCE)

    start = (SINCE - OVERLAP).isoformat()
    assert query == (
        f"(SELECT * FROM transactions WHERE updated_at >= '{start}') AS src"
    )


def test_refunds_use_created_at_as_watermark():
    assert "WHERE created_at >=" in extract_query("refunds", SINCE)


def test_cancellations_use_created_at_as_watermark():
    assert "WHERE created_at >=" in extract_query("cancellations", SINCE)


def test_accounts_is_always_a_full_read():
    assert extract_query("accounts", SINCE) == "(SELECT * FROM accounts) AS src"


def test_missing_since_reads_whole_table():
    assert extract_query("transactions", None) == "(SELECT * FROM transactions) AS src"


def test_unknown_table_is_rejected():
    with pytest.raises(ValueError):
        extract_query("api_clients", SINCE)


def test_table_name_cannot_inject_sql():
    with pytest.raises(ValueError):
        extract_query("transactions; DROP TABLE accounts", SINCE)
