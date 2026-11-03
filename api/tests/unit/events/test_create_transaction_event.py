"""Tests that the create-transfer route queues an event only for a new transfer.

What this file does:
    Calls the route function with the database and the transfer service replaced by fakes.
    No database and no AWS connection are used.
"""

from contextlib import contextmanager
from datetime import datetime, timezone
from decimal import Decimal
from uuid import uuid4

import pytest
from fastapi import BackgroundTasks, Response

from presentation import main
from validation.schemas import TransactionCreate

ROW = {
    "transaction_id": uuid4(),
    "from_account_id": uuid4(),
    "to_account_id": uuid4(),
    "amount": Decimal("10.00"),
    "currency": "USD",
    "description": "test",
    "status": "completed",
    "created_at": datetime.now(timezone.utc),
    "updated_at": datetime.now(timezone.utc),
    "version": 1,
}


class FakeTransferService:
    result = None

    def __init__(self, conn, client_id):
        pass

    def create(self, key, data):
        return FakeTransferService.result


@pytest.fixture
def queued(monkeypatch):
    """Replaces the database, the API key check, and the publisher. Returns the list of queued events."""
    sent = []

    @contextmanager
    def fake_connect():
        yield None

    monkeypatch.setattr(main, "connect", fake_connect)
    monkeypatch.setattr(main, "check_api_key", lambda conn, api_key: uuid4())
    monkeypatch.setattr(main.banking, "TransferService", FakeTransferService)
    monkeypatch.setattr(main.events, "publish_transfer_created", lambda event: sent.append(event))
    return sent


def call_route(**overrides):
    payload = TransactionCreate(source="Ali", destination="Sara", amount=Decimal("10.00"), currency="USD", description="test")
    background = BackgroundTasks()
    main.create_transaction(
        payload=payload,
        response=Response(),
        background_tasks=background,
        x_api_key="key",
        idempotency_key=str(uuid4()),
        **overrides,
    )
    return background


def test_new_transfer_queues_one_event(queued):
    FakeTransferService.result = (ROW, True)

    background = call_route()
    for task in background.tasks:
        task.func(*task.args, **task.kwargs)

    assert len(background.tasks) == 1
    assert queued[0]["txn_id"] == str(ROW["transaction_id"])


def test_retried_transfer_queues_no_event(queued):
    FakeTransferService.result = (ROW, False)

    background = call_route()

    assert background.tasks == []
    assert queued == []
