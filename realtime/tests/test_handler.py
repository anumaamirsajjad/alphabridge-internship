# Tests for the Lambda handler. They use a fake S3 client, so they run anywhere without AWS.

import json
import os
import sys
from decimal import Decimal
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lambda"))

import handler  # noqa: E402
from handler import lambda_handler, to_row  # noqa: E402


class FakeS3:
    def __init__(self, error=None):
        self.objects = []
        self.error = error

    def put_object(self, Bucket, Key, Body, ContentType):
        if self.error:
            raise self.error
        self.objects.append((Bucket, Key, Body.decode("utf-8")))


def event(txn_id="t1", amount="250.00", event_id=None):
    return json.dumps({
        "event_id": event_id or f"e-{txn_id}",
        "event_type": "transfer.created",
        "txn_id": txn_id,
        "from_account": "a1",
        "to_account": "a2",
        "amount": amount,
        "currency": "USD",
        "status": "completed",
        "event_time": "2026-11-03T10:00:00+00:00",
    })


def sqs(*bodies):
    return {"Records": [{"messageId": f"m{i}", "body": body} for i, body in enumerate(bodies)]}


@pytest.fixture(autouse=True)
def bucket(monkeypatch):
    monkeypatch.setenv("GOLD_BUCKET", "alphabridge-lake-gold-169774886945")
    monkeypatch.setenv("LARGE_TRANSACTION_THRESHOLD", "10000")


def rows_written(s3):
    return [json.loads(line) for _, _, body in s3.objects for line in body.splitlines()]


def test_large_transaction_is_flagged():
    s3 = FakeS3()
    lambda_handler(sqs(event(amount="10000.00")), None, s3=s3)
    assert rows_written(s3)[0]["is_large"] is True


def test_small_transaction_is_not_flagged():
    s3 = FakeS3()
    lambda_handler(sqs(event(amount="249.99")), None, s3=s3)
    assert rows_written(s3)[0]["is_large"] is False


def test_threshold_comes_from_the_environment(monkeypatch):
    monkeypatch.setenv("LARGE_TRANSACTION_THRESHOLD", "100")
    assert to_row(json.loads(event(amount="150.00")), Decimal(os.environ["LARGE_TRANSACTION_THRESHOLD"]))["is_large"] is True


def test_one_batch_is_one_file_in_the_gold_bucket():
    s3 = FakeS3()
    lambda_handler(sqs(event("t1"), event("t2"), event("t3")), None, s3=s3)

    assert len(s3.objects) == 1
    bucket, key, _ = s3.objects[0]
    assert bucket == "alphabridge-lake-gold-169774886945"
    assert key.startswith("realtime/transactions/dt=")
    assert len(rows_written(s3)) == 3


def test_duplicate_messages_are_written_and_left_for_athena_to_dedupe():
    s3 = FakeS3()
    lambda_handler(sqs(event("t1", event_id="same"), event("t1", event_id="same")), None, s3=s3)
    assert [row["event_id"] for row in rows_written(s3)] == ["same", "same"]


def test_bad_message_is_reported_back_and_others_are_saved():
    s3 = FakeS3()
    result = lambda_handler(sqs(event("t1"), "not json", event("t3")), None, s3=s3)

    assert result == {"batchItemFailures": [{"itemIdentifier": "m1"}]}
    assert [row["txn_id"] for row in rows_written(s3)] == ["t1", "t3"]


def test_missing_field_is_reported_back():
    s3 = FakeS3()
    body = json.dumps({"event_id": "e1", "txn_id": "t1"})
    result = lambda_handler(sqs(body), None, s3=s3)
    assert result == {"batchItemFailures": [{"itemIdentifier": "m0"}]}


def test_failed_write_retries_the_whole_batch():
    s3 = FakeS3(error=ConnectionError("s3 down"))
    result = lambda_handler(sqs(event("t1"), event("t2")), None, s3=s3)
    assert result == {"batchItemFailures": [{"itemIdentifier": "m0"}, {"itemIdentifier": "m1"}]}


def test_handler_refuses_to_run_without_a_bucket(monkeypatch):
    monkeypatch.delenv("GOLD_BUCKET")
    with pytest.raises(RuntimeError):
        lambda_handler(sqs(event()), None, s3=FakeS3())
