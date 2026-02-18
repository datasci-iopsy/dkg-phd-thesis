"""Pub/Sub publishing utilities for async message passing.

Provides typed message models and publishing functions for
inter-function communication via Pub/Sub. The message models
are shared between publishers and subscribers to keep the
contract explicit.

Design note: `google-cloud-pubsub` (pubsub_v1) is imported
lazily inside the publishing functions rather than at module
level. This allows subscriber functions (e.g., run-intake-
confirmation) to import IntakeProcessedMessage without
declaring google-cloud-pubsub as a dependency -- they never
publish, so they should never pay the import cost or require
the package.
"""

import json
import logging

from pydantic import BaseModel, Field

from .config_models import AppConfig

logger = logging.getLogger(__name__)


# -- Message models ------------------------------------------------


class IntakeProcessedMessage(BaseModel):
    """Pub/Sub message payload for processed intake responses.

    Published by run-qualtrics-scheduling after a successful
    BigQuery write. Consumed by run-intake-confirmation to
    send SMS confirmations and update _processed status.

    Contains only the fields the confirmation function needs.
    The full survey response lives in BigQuery.
    """

    response_id: str = Field(
        ..., description="Qualtrics response ID (idempotency key)"
    )
    phone: str = Field(..., description="E.164 formatted phone number")
    selected_date: str = Field(
        ..., description="Participant's chosen date (ISO format, YYYY-MM-DD)"
    )
    timezone: str = Field(..., description="IANA timezone (e.g., US/Central)")


# -- Publishing ----------------------------------------------------


def get_publisher_client():
    """Initialize a Pub/Sub publisher client.

    Imports google-cloud-pubsub lazily so that subscriber
    functions importing this module don't require the package.

    Returns:
        Authenticated PublisherClient using ADC.
    """
    from google.cloud import pubsub_v1

    return pubsub_v1.PublisherClient()


def publish_intake_processed(
    message: IntakeProcessedMessage,
    config: AppConfig,
) -> str | None:
    """Publish an intake-processed message to Pub/Sub.

    Serializes the message as JSON and publishes it to the
    topic configured in config.pubsub.topic_id. Returns the
    published message ID on success, or None on failure.

    Args:
        message: Validated message payload with participant
            scheduling data.
        config: Application config with Pub/Sub topic reference.

    Returns:
        Pub/Sub message ID string, or None if publishing failed.
    """
    if not config.pubsub:
        logger.error(
            "Pub/Sub config not found -- cannot publish message "
            "for response %s",
            message.response_id,
        )
        return None

    try:
        client = get_publisher_client()
        topic_path = client.topic_path(
            config.gcp.project_id, config.pubsub.topic_id
        )
        data = json.dumps(message.model_dump()).encode("utf-8")
        future = client.publish(topic_path, data=data)
        message_id = future.result()
        logger.info(
            "Published intake-processed message for %s "
            "(message_id: %s, topic: %s)",
            message.response_id,
            message_id,
            config.pubsub.topic_id,
        )
        return message_id

    except Exception as e:
        logger.error(
            "Failed to publish message for %s: %s",
            message.response_id,
            e,
            exc_info=True,
        )
        return None
