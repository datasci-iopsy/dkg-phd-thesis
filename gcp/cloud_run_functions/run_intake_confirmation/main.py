"""Cloud Function entry point for intake confirmation SMS.

Triggered by Pub/Sub messages published after a successful
intake survey write to BigQuery. Sends a Twilio SMS confirming
the participant's follow-up survey schedule, then marks the
BigQuery row as processed.

Workflow:
    1. Decode and validate the Pub/Sub message
    2. Check idempotency (_processed status in BigQuery)
    3. Send confirmation SMS via Twilio
    4. Update _processed = TRUE in BigQuery

Idempotency:
    If the message is retried (e.g., after a transient failure),
    the function checks _processed before sending SMS. If the
    row is already marked TRUE, the function skips SMS and
    acknowledges the message. This prevents duplicate texts on
    Pub/Sub redelivery.

Twilio credentials are stored as a single JSON secret in
Secret Manager and injected as the TWILIO_CONFIG environment
variable at deploy time (configured in functions.yaml).
"""

import base64
import json
import logging
import os
from datetime import date, time
from pathlib import Path

import functions_framework
from cloudevents.http import CloudEvent
from google.cloud import bigquery
from shared.utils.config_loader import load_config
from shared.utils.pubsub_utils import IntakeProcessedMessage

# -- Logging ---------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

# -- Configuration (loaded once at cold start) -----------------------
_config_path = Path(__file__).resolve().parent / "configs"
config = load_config(_config_path)
logger.info("Loaded config sections: %s", list(config.model_fields.keys()))

# -- Twilio credentials (from Secret Manager via env vars) -----------
# Stored as a single JSON secret in Secret Manager and injected
# as TWILIO_CONFIG at deploy time. Parsed once at cold start.
#
# Expected JSON format:
#   {"account_sid": "AC...", "auth_token": "...", "from_number": "+1..."}
_twilio_raw = os.environ.get("TWILIO_CONFIG", "{}")
try:
    _twilio_config = json.loads(_twilio_raw)
except json.JSONDecodeError:
    logger.error("TWILIO_CONFIG is not valid JSON")
    _twilio_config = {}

TWILIO_ACCOUNT_SID: str = _twilio_config.get("account_sid", "")
TWILIO_AUTH_TOKEN: str = _twilio_config.get("auth_token", "")
TWILIO_FROM_NUMBER: str = _twilio_config.get("from_number", "")

# -- Follow-up schedule constants ------------------------------------
# Fixed daily survey times matching ParticipantData.followup_times
# in the scheduling function. Defined here to keep the confirmation
# function self-contained without cross-function imports.
FOLLOWUP_TIMES: list[time] = [time(9, 0), time(13, 0), time(17, 0)]


# -- Helpers ---------------------------------------------------------
def decode_pubsub_message(cloud_event: CloudEvent) -> dict | None:
    """Decode and parse the Pub/Sub message from a CloudEvent.

    Gen2 Cloud Run functions receive Pub/Sub messages wrapped
    in a CloudEvent envelope. The actual message data is
    base64-encoded JSON inside cloud_event.data["message"]["data"].

    Args:
        cloud_event: CloudEvent from Pub/Sub push subscription.

    Returns:
        Parsed message dict, or None if decoding fails.
    """
    try:
        encoded = cloud_event.data["message"]["data"]
        decoded = base64.b64decode(encoded)
        return json.loads(decoded)
    except (KeyError, TypeError) as e:
        logger.error("Malformed CloudEvent structure: %s", e)
        return None
    except (json.JSONDecodeError, ValueError) as e:
        logger.error("Failed to decode message data: %s", e)
        return None


def is_already_processed(client: bigquery.Client, response_id: str) -> bool:
    """Check whether a response has already been processed.

    Queries the _processed flag in BigQuery. Returns True if
    the row exists and _processed is TRUE, preventing duplicate
    SMS on Pub/Sub redelivery.

    Args:
        client: BigQuery client.
        response_id: Qualtrics response ID to check.

    Returns:
        True if already processed, False otherwise.
    """
    full_table_id = (
        f"{config.gcp.project_id}.{config.bq.dataset_id}"
        f".{config.bq.tables.intake_raw}"
    )

    query = f"""
        SELECT _processed
        FROM `{full_table_id}`
        WHERE response_id = @response_id
        LIMIT 1
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("response_id", "STRING", response_id)
        ]
    )

    rows = list(client.query(query, job_config=job_config).result())

    if not rows:
        logger.warning(
            "No row found for response %s -- may still be in streaming buffer",
            response_id,
        )
        return False

    return bool(rows[0]._processed)


def update_processed_flag(client: bigquery.Client, response_id: str) -> bool:
    """Set _processed = TRUE for a specific response in BigQuery.

    Uses a DML UPDATE with a WHERE guard on _processed = FALSE
    for safety. Returns True if the update affected exactly one
    row.

    Args:
        client: BigQuery client.
        response_id: Qualtrics response ID to update.

    Returns:
        True if the update succeeded, False otherwise.
    """
    full_table_id = (
        f"{config.gcp.project_id}.{config.bq.dataset_id}"
        f".{config.bq.tables.intake_raw}"
    )

    query = f"""
        UPDATE `{full_table_id}`
        SET _processed = TRUE
        WHERE response_id = @response_id
          AND _processed = FALSE
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("response_id", "STRING", response_id)
        ]
    )

    try:
        result = client.query(query, job_config=job_config).result()
        affected = result.num_dml_affected_rows or 0

        if affected == 1:
            logger.info("Marked response %s as processed", response_id)
            return True
        elif affected == 0:
            logger.warning(
                "UPDATE affected 0 rows for %s -- may already be processed",
                response_id,
            )
            return True
        else:
            logger.error(
                "UPDATE affected %d rows for %s -- expected 0 or 1",
                affected,
                response_id,
            )
            return False

    except Exception as e:
        logger.error(
            "Failed to update _processed for %s: %s",
            response_id,
            e,
            exc_info=True,
        )
        return False


def format_sms_body(selected_date: date, timezone: str) -> str:
    """Build the confirmation SMS message body.

    Formats the participant's follow-up schedule into a concise
    text message with their selected date and survey times.

    Args:
        selected_date: Participant's chosen follow-up date.
        timezone: IANA timezone label (e.g., US/Central).

    Returns:
        Formatted SMS body string.
    """
    date_str = selected_date.strftime("%B %d, %Y")

    time_parts = []
    for t in FOLLOWUP_TIMES:
        hour = t.hour
        period = "AM" if hour < 12 else "PM"
        display_hour = hour if hour <= 12 else hour - 12
        if display_hour == 0:
            display_hour = 12
        time_parts.append(f"{display_hour}:{t.minute:02d} {period}")

    times_str = ", ".join(time_parts[:-1]) + f", and {time_parts[-1]}"

    return (
        f"Thank you for participating in our study! "
        f"We received your selected follow-up date: {date_str}. "
        f"You will receive surveys at {times_str} ({timezone})."
    )


def send_sms(phone: str, body: str) -> bool:
    """Send an SMS message via Twilio.

    Imports the Twilio client lazily to keep cold start fast
    when credentials are missing (e.g., local testing without
    Twilio configured).

    Args:
        phone: E.164 formatted recipient phone number.
        body: Message text to send.

    Returns:
        True if the message was accepted by Twilio, False otherwise.
    """
    if not all([TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM_NUMBER]):
        logger.error(
            "Twilio credentials not configured -- check "
            "TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, and "
            "TWILIO_FROM_NUMBER environment variables"
        )
        return False

    try:
        from twilio.rest import Client as TwilioClient

        client = TwilioClient(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
        message = client.messages.create(
            body=body,
            from_=TWILIO_FROM_NUMBER,
            to=phone,
        )

        logger.info(
            "SMS sent to %s (Twilio SID: %s, status: %s)",
            phone[:2] + "***" + phone[-4:],
            message.sid,
            message.status,
        )
        return True

    except Exception as e:
        logger.error(
            "Twilio SMS failed for %s: %s",
            phone[:2] + "***" + phone[-4:],
            e,
            exc_info=True,
        )
        return False


# -- Entry point -----------------------------------------------------
@functions_framework.cloud_event
def intake_confirmation_handler(cloud_event: CloudEvent) -> None:
    """Handle Pub/Sub messages for intake response confirmation.

    Decodes the message, verifies idempotency, sends an SMS
    confirmation via Twilio, and marks the BigQuery row as
    processed.

    If any step fails, the function raises an exception so
    Pub/Sub does not acknowledge the message and retries
    with exponential backoff.

    Args:
        cloud_event: CloudEvent containing the Pub/Sub message
            with IntakeProcessedMessage data.
    """
    # Step 1: Decode the Pub/Sub message
    raw = decode_pubsub_message(cloud_event)
    if raw is None:
        # Malformed message -- log and return (acknowledge) to
        # prevent infinite retries on permanently bad data.
        logger.error("Could not decode message -- acknowledging to skip")
        return

    try:
        message = IntakeProcessedMessage.model_validate(raw)
    except Exception as e:
        logger.error("Message validation failed: %s (data: %s)", e, raw)
        return

    logger.info(
        "Processing confirmation for response %s (phone: %s***%s)",
        message.response_id,
        message.phone[:2],
        message.phone[-4:],
    )

    # Step 2: Idempotency check
    bq_client = bigquery.Client(project=config.gcp.project_id)

    if is_already_processed(bq_client, message.response_id):
        logger.info(
            "Response %s already processed -- skipping SMS",
            message.response_id,
        )
        return

    # Step 3: Send confirmation SMS
    selected_date = date.fromisoformat(message.selected_date)
    body = format_sms_body(selected_date, message.timezone)

    sms_sent = send_sms(message.phone, body)
    if not sms_sent:
        # Raise to trigger Pub/Sub retry
        raise RuntimeError(
            f"SMS failed for response {message.response_id} "
            f"-- will retry via Pub/Sub"
        )

    # Step 4: Mark as processed in BigQuery
    updated = update_processed_flag(bq_client, message.response_id)
    if not updated:
        # SMS was sent but flag update failed. Log the gap.
        # On retry, idempotency check may pass (if the UPDATE
        # eventually succeeded) or SMS sends again (acceptable
        # for small sample).
        logger.warning(
            "SMS sent but _processed update failed for %s -- "
            "may result in duplicate SMS on retry",
            message.response_id,
        )

    logger.info(
        "Confirmation complete for response %s (sms: %s, updated: %s)",
        message.response_id,
        sms_sent,
        updated,
    )
