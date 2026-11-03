"""Tests for the transfer.created event: its contents, sending, and failure handling.

What this file does:
    Uses a fake SQS client, so nothing is sent to AWS. Covers the event fields, the
    "do nothing when not configured" rule, and that a failed send never raises.
"""

import json
import logging
from datetime import datetime, timezone
from decimal import Decimal
from uuid import uuid4

import pytest

import events

TRANSFER = {
    "transaction_id": uuid4(),
    "from_account_id": uuid4(),
    "to_account_id": uuid4(),
    "amount": Decimal("250.00"),
    "currency": "USD",
    "status": "completed",
}


class FakeSqs:
    def __init__(self, error=None):
        self.sent = []
        self.error = error

    def send_message(self, QueueUrl, MessageBody):
        if self.error:
            raise self.error
        self.sent.append((QueueUrl, MessageBody))


@pytest.fixture
def queue_url(monkeypatch):
    url = "https://sqs.ap-south-1.amazonaws.com/169774886945/alphabridge-transaction-events"
    monkeypatch.setenv("EVENTS_QUEUE_URL", url)
    return url


def test_event_has_all_required_fields():
    event = events.build_event(TRANSFER)

    assert set(event) == {
        "event_id", "event_type", "txn_id", "from_account", "to_account",
        "amount", "currency", "status", "event_time",
    }
    assert event["event_type"] == "transfer.created"
    assert event["txn_id"] == str(TRANSFER["transaction_id"])
    assert event["amount"] == "250.00"
    assert event["currency"] == "USD"


def test_each_event_gets_a_new_event_id():
    assert events.build_event(TRANSFER)["event_id"] != events.build_event(TRANSFER)["event_id"]


def test_event_time_is_utc():
    event_time = datetime.fromisoformat(events.build_event(TRANSFER)["event_time"])
    assert event_time.utcoffset() == timezone.utc.utcoffset(None)


def test_event_is_sent_to_the_queue(queue_url):
    fake = FakeSqs()
    event = events.build_event(TRANSFER)

    events.publish_transfer_created(event, client=fake)

    assert len(fake.sent) == 1
    sent_url, body = fake.sent[0]
    assert sent_url == queue_url
    assert json.loads(body) == event


def test_nothing_is_sent_when_no_queue_is_configured(monkeypatch):
    monkeypatch.delenv("EVENTS_QUEUE_URL", raising=False)
    fake = FakeSqs()

    events.publish_transfer_created(events.build_event(TRANSFER), client=fake)

    assert fake.sent == []


def test_a_failed_send_is_logged_and_never_raised(queue_url, caplog):
    fake = FakeSqs(error=ConnectionError("network down"))

    with caplog.at_level(logging.ERROR):
        events.publish_transfer_created(events.build_event(TRANSFER), client=fake)

    assert "ConnectionError" in caplog.text
    assert "network down" not in caplog.text  # only the error type is logged
