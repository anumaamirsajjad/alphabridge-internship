# What this file does:
#   Tests the whole event path on LocalStack (a fake AWS in Docker):
#     1. creates the queue, the dead-letter queue, and the gold bucket
#     2. sends transfer events, including a repeat, a large transfer, and a bad message
#     3. reads the queue and runs the real Lambda handler on the messages
#     4. checks the files written to the bucket
#
#   Start LocalStack first (see realtime/local/docker-compose.yml), then run:
#     python realtime/local/run_local.py
#
#   It needs no AWS login. It points boto3 at LocalStack only, and only for this process.

import json
import os
import sys
import uuid
from pathlib import Path

import boto3

ENDPOINT = "http://localhost:4566"
REGION = "ap-south-1"
BUCKET = "alphabridge-lake-gold-local"
QUEUE = "alphabridge-transaction-events"
DLQ = "alphabridge-transaction-events-dlq"

# Lets handler.py use LocalStack too, without any change to the handler.
os.environ.update({
    "AWS_ENDPOINT_URL": ENDPOINT,
    "AWS_ACCESS_KEY_ID": "test",
    "AWS_SECRET_ACCESS_KEY": "test",
    "AWS_DEFAULT_REGION": REGION,
    "GOLD_BUCKET": BUCKET,
    "LARGE_TRANSACTION_THRESHOLD": "10000",
})

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lambda"))
from handler import lambda_handler  # noqa: E402


def client(service):
    return boto3.client(service, endpoint_url=ENDPOINT, region_name=REGION,
                        aws_access_key_id="test", aws_secret_access_key="test")


def event(txn_id, amount, event_id=None):
    return json.dumps({
        "event_id": event_id or str(uuid.uuid4()),
        "event_type": "transfer.created",
        "txn_id": txn_id,
        "from_account": str(uuid.uuid4()),
        "to_account": str(uuid.uuid4()),
        "amount": amount,
        "currency": "USD",
        "status": "completed",
        "event_time": "2026-11-03T10:00:00+00:00",
    })


def main():
    sqs, s3 = client("sqs"), client("s3")

    dlq_url = sqs.create_queue(QueueName=DLQ)["QueueUrl"]
    dlq_arn = sqs.get_queue_attributes(QueueUrl=dlq_url, AttributeNames=["QueueArn"])["Attributes"]["QueueArn"]
    queue_url = sqs.create_queue(QueueName=QUEUE, Attributes={
        "RedrivePolicy": json.dumps({"deadLetterTargetArn": dlq_arn, "maxReceiveCount": "5"}),
    })["QueueUrl"]
    s3.create_bucket(Bucket=BUCKET, CreateBucketConfiguration={"LocationConstraint": REGION})

    repeated_id = str(uuid.uuid4())
    for body in [
        event("t-small", "250.00"),
        event("t-large", "25000.00"),
        event("t-repeat", "300.00", event_id=repeated_id),
        event("t-repeat", "300.00", event_id=repeated_id),  # the same event twice
        "this is not json",                                  # a bad message
    ]:
        sqs.send_message(QueueUrl=queue_url, MessageBody=body)

    messages = sqs.receive_message(QueueUrl=queue_url, MaxNumberOfMessages=10)["Messages"]
    records = [{"messageId": m["MessageId"], "body": m["Body"]} for m in messages]
    result = lambda_handler({"Records": records}, None)

    failed = {f["itemIdentifier"] for f in result["batchItemFailures"]}
    assert len(failed) == 1, f"expected one bad message, got {len(failed)}"

    objects = s3.list_objects_v2(Bucket=BUCKET, Prefix="realtime/transactions/").get("Contents", [])
    assert len(objects) == 1, f"expected one file for the batch, got {len(objects)}"

    body = s3.get_object(Bucket=BUCKET, Key=objects[0]["Key"])["Body"].read().decode()
    rows = [json.loads(line) for line in body.splitlines()]
    flags = {row["txn_id"]: row["is_large"] for row in rows}

    assert len(rows) == 4, f"expected 4 rows (repeat kept for Athena to remove), got {len(rows)}"
    assert flags["t-large"] is True, "a 25000 transfer must be flagged"
    assert flags["t-small"] is False, "a 250 transfer must not be flagged"
    print("LOCAL CHECK PASSED")
    print(f"  bad messages reported back: {len(failed)}")
    print(f"  rows written to the file: {len(rows)} (duplicates are removed later, in Athena)")
    print(f"  file: s3://{BUCKET}/{objects[0]['Key']}")


if __name__ == "__main__":
    main()
