# What this file does:
#   Builds the SQL that Glue reads from the source database.
#   Each table is listed with the column that tells us when a row last changed.
#   The table name is checked against this list, so nothing unexpected reaches the query.
#
# Why a small overlap: a row whose transaction commits a moment late can carry an
# updated_at earlier than the last run's watermark. Re-reading a short window before the
# watermark catches those rows. The Silver step removes the duplicates this creates.

from datetime import datetime, timedelta

# Table name -> the column that marks a change. None means no watermark: read the whole table.
WATERMARKS = {
    "transactions": "updated_at",
    "refunds": "created_at",
    "cancellations": "created_at",
    "accounts": None,  # No updated_at column in the source, so accounts is fully reloaded.
}

OVERLAP = timedelta(minutes=10)


def extract_query(table, since):
    """Return the subquery Spark reads from the source for one table."""
    if table not in WATERMARKS:
        raise ValueError(f"table not allowed: {table}")

    column = WATERMARKS[table]
    if column is None or since is None:
        return f"(SELECT * FROM {table}) AS src"

    start = since - OVERLAP
    return f"(SELECT * FROM {table} WHERE {column} >= '{start.isoformat()}') AS src"
