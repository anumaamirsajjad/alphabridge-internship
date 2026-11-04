"""Sends a "transfer.created" event to the events queue after a transfer is saved.

What this file does:
    Builds the event from a saved transfer and sends it to an SQS queue.
    The send runs after the response (FastAPI background task), so the user never waits for it.
    A failed send is logged by type only and never raised, so it cannot fail the transfer.

Configuration (environment variables):
    EVENTS_QUEUE_URL   the SQS queue URL. If it is not set, nothing is sent.
    AWS_REGION         the region of the queue (default ap-south-1).
"""

import json
import logging
import os
from datetime import datetime, timezone
from uuid import uuid4

import boto3

logger = logging.getLogger(__name__)

EVENT_TYPE = "transfer.created"


def build_event(transfer):
    """Turn a saved transfer row into the event message."""
    return {
        "event_id": str(uuid4()),
        "event_type": EVENT_TYPE,
        "txn_id": str(transfer["transaction_id"]),
        "from_account": str(transfer["from_account_id"]),
        "to_account": str(transfer["to_account_id"]),
        "amount": str(transfer["amount"]),
        "currency": transfer["currency"].strip(),
        "status": transfer["status"],
        "event_time": datetime.now(timezone.utc).isoformat(),
    }


def publish_transfer_created(event, client=None):
    """Send one event to the queue. Never raises: a failure is logged and the function returns."""
    queue_url = os.getenv("EVENTS_QUEUE_URL")
    if not queue_url:
        return

    try:
        sqs = client or boto3.client("sqs", region_name=os.getenv("AWS_REGION", "ap-south-1"))
        sqs.send_message(QueueUrl=queue_url, MessageBody=json.dumps(event))
    except Exception as error:
        # Only the error type is logged. The message can contain account or request details.
        logger.error("Event publish failed for %s: %s", event.get("txn_id"), type(error).__name__)
