# What this file does:
#   Lambda function. Reads transfer.created events from the SQS queue, flags large transfers,
#   and writes the batch to the gold bucket in S3 as one JSON-lines file.
#
#   Duplicates: SQS can deliver a message twice, and the same event may be written twice. That is
#   fine here. The Athena view keeps one row per event_id, so reports never count a transfer twice.
#
#   Failures: a bad message is reported back to SQS alone, so only that message is retried. If the
#   S3 write fails, every message in the batch is retried. After 5 failed attempts a message moves
#   to the dead-letter queue (see realtime/infra/queue.tf).
#
# Configuration (environment variables):
#   GOLD_BUCKET                   the S3 bucket for the gold layer (required)
#   LARGE_TRANSACTION_THRESHOLD   amounts at or above this are flagged (default 10000, a placeholder)

import json
import os
import uuid
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation

import boto3

# Placeholder. The real threshold is a business decision. Set LARGE_TRANSACTION_THRESHOLD to change it.
DEFAULT_LARGE_TRANSACTION_THRESHOLD = "10000"

REQUIRED_FIELDS = ("event_id", "txn_id", "from_account", "to_account", "amount", "currency", "status", "event_time")
OUTPUT_PREFIX = "realtime/transactions"


def large_transaction_threshold():
    return Decimal(os.environ.get("LARGE_TRANSACTION_THRESHOLD", DEFAULT_LARGE_TRANSACTION_THRESHOLD))


def parse_event(body):
    """Read one message body. Raises ValueError if a field is missing or the amount is not a number."""
    event = json.loads(body)
    missing = [field for field in REQUIRED_FIELDS if field not in event]
    if missing:
        raise ValueError(f"missing fields: {missing}")
    try:
        Decimal(str(event["amount"]))
    except InvalidOperation as error:
        raise ValueError("bad amount") from error
    return event


def to_row(event, threshold):
    """The row written to S3: the event plus the flag and the time it was processed."""
    return {
        **event,
        "is_large": Decimal(str(event["amount"])) >= threshold,
        "processed_at": datetime.now(timezone.utc).isoformat(),
    }


def object_key(processed_at):
    """Folders by hour, so Athena can skip the hours it does not need."""
    stamp = datetime.fromisoformat(processed_at)
    return (
        f"{OUTPUT_PREFIX}/dt={stamp:%Y-%m-%d}/hour={stamp:%H}/"
        f"{stamp:%Y%m%dT%H%M%S}-{uuid.uuid4().hex}.json"
    )


def write_rows(rows, bucket, s3=None):
    """Write one batch as a JSON-lines file. Does nothing when there are no rows."""
    if not rows:
        return
    client = s3 or boto3.client("s3")
    body = "\n".join(json.dumps(row, default=str) for row in rows) + "\n"
    client.put_object(
        Bucket=bucket,
        Key=object_key(rows[0]["processed_at"]),
        Body=body.encode("utf-8"),
        ContentType="application/json",
    )


def lambda_handler(sqs_event, context, s3=None):
    """Entry point for SQS. Returns the IDs of the messages that failed, so SQS retries only those."""
    bucket = os.environ.get("GOLD_BUCKET")
    if not bucket:
        raise RuntimeError("GOLD_BUCKET is not set")

    threshold = large_transaction_threshold()
    rows = []
    failures = []

    for record in sqs_event["Records"]:
        try:
            rows.append(to_row(parse_event(record["body"]), threshold))
        except (ValueError, KeyError, json.JSONDecodeError):
            failures.append({"itemIdentifier": record["messageId"]})

    try:
        write_rows(rows, bucket, s3=s3)
    except Exception:
        # The batch could not be saved, so every message in it is retried.
        return {"batchItemFailures": [{"itemIdentifier": r["messageId"]} for r in sqs_event["Records"]]}

    return {"batchItemFailures": failures}
