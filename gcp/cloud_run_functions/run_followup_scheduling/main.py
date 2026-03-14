"""Cloud Function entry point for follow-up survey SMS scheduling.

Triggered by Pub/Sub messages published after a successful intake
confirmation SMS. Schedules three follow-up survey SMS messages
via the Twilio Message Scheduling API -- one for each daily survey
time slot (9:00 AM, 1:00 PM, 5:00 PM in the participant's timezone).

Workflow:
    1. Decode and validate the Pub/Sub message
    2. Check idempotency (_scheduled status in BigQuery)
    3. Build survey URLs with participant-specific query params
    4. Schedule three SMS messages via Twilio (15 min - 35 day window)
    5. Write scheduling records to BigQuery (message SIDs for audit)

Idempotency:
    Uses the scheduled_followups BigQuery table keyed by
    response_id. If records with _scheduled=TRUE already exist,
    the function skips scheduling and acknowledges the message.
    Records are only written after ALL three Twilio calls succeed.

Twilio credentials are stored as a single JSON secret in
Secret Manager and injected as the TWILIO_CONFIG environment
variable at deploy time. Must include messaging_service_sid
for scheduled messages (in addition to account_sid, auth_token).
"""

import base64
import json
import logging
import os
import zoneinfo
from datetime import UTC, date, datetime, time, timedelta
from pathlib import Path
from urllib.parse import urlencode

import functions_framework
from cloudevents.http import CloudEvent
from google.cloud import bigquery
from shared.utils.config_loader import load_config
from shared.utils.pubsub_utils import FollowupSchedulingMessage

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
# Expected JSON format:
#   {
#       "account_sid": "AC...",
#       "auth_token": "...",
#       "from_number": "+1...",
#       "messaging_service_sid": "MG..."
#   }
# This function reads messaging_service_sid (required for scheduling)
# instead of from_number (used by the confirmation function).
_twilio_raw = os.environ.get("TWILIO_CONFIG", "{}")
try:
    _twilio_config = json.loads(_twilio_raw)
except json.JSONDecodeError:
    logger.error("TWILIO_CONFIG is not valid JSON")
    _twilio_config = {}

TWILIO_ACCOUNT_SID: str = _twilio_config.get("account_sid", "")
TWILIO_AUTH_TOKEN: str = _twilio_config.get("auth_token", "")
TWILIO_MESSAGING_SERVICE_SID: str = _twilio_config.get(
    "messaging_service_sid", ""
)

# -- Follow-up schedule constants ------------------------------------
# Fixed daily survey times matching ParticipantData.followup_times
# in the scheduling function. Order must match config survey_ids.
FOLLOWUP_TIMES: list[time] = [time(9, 0), time(13, 0), time(17, 0)]

# Twilio requires send_at to be 15–35 days in the future.
# Use 16 min as a buffer so we never hit the boundary.
MIN_SCHEDULE_LEAD = timedelta(minutes=16)


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


def build_survey_url(
    survey_id: str,
    response_id: str,
    prolific_pid: str | None,
    survey_time: int,
    selected_date: str,
) -> str:
    """Construct a follow-up survey URL with query parameters.

    Builds a URL-encoded link to a Qualtrics follow-up survey
    with embedded metadata for response linking. prolific_pid
    is omitted from the URL when it is None.

    Args:
        survey_id: Qualtrics survey ID for this time slot.
        response_id: Original intake response ID.
        prolific_pid: Prolific PID (omitted from URL if None).
        survey_time: Time slot number (1, 2, or 3).
        selected_date: ISO date string (YYYY-MM-DD).

    Returns:
        Complete URL with query parameters.
    """
    base_url = config.followup_surveys.survey_base_url

    params: dict[str, str | int] = {
        "response_id": response_id,
        "survey_time": survey_time,
        "selected_date": selected_date,
    }

    if prolific_pid is not None:
        params["prolific_pid"] = prolific_pid

    query_string = urlencode(params)
    return f"{base_url}/{survey_id}?{query_string}"


def compute_send_at(
    selected_date: date,
    survey_time: time,
    timezone_str: str,
) -> datetime:
    """Compute the UTC datetime for a scheduled SMS send.

    Combines the participant's selected date and survey time
    in their local timezone, then converts to UTC for the
    Twilio scheduling API.

    Args:
        selected_date: Date for the follow-up survey.
        survey_time: Local time for delivery.
        timezone_str: IANA timezone (e.g., US/Central).

    Returns:
        UTC datetime for the Twilio send_at parameter.

    Raises:
        KeyError: If the timezone string is not recognized.
    """
    tz = zoneinfo.ZoneInfo(timezone_str)
    local_dt = datetime.combine(selected_date, survey_time, tzinfo=tz)
    return local_dt.astimezone(zoneinfo.ZoneInfo("UTC"))


def format_time_label(survey_time: time) -> str:
    """Format a time object as a 12-hour string (e.g., '9:00 AM').

    Args:
        survey_time: Time to format.

    Returns:
        Formatted time string.
    """
    hour = survey_time.hour
    period = "AM" if hour < 12 else "PM"
    display_hour = hour if hour <= 12 else hour - 12
    if display_hour == 0:
        display_hour = 12
    return f"{display_hour}:{survey_time.minute:02d} {period}"


def schedule_sms(
    phone: str,
    body: str,
    send_at: datetime,
) -> str | None:
    """Schedule an SMS message via Twilio Message Scheduling API.

    Uses messaging_service_sid (required for scheduled messages)
    instead of from_number. Lazily imports Twilio client.

    Args:
        phone: E.164 formatted recipient phone number.
        body: Message text to send.
        send_at: UTC datetime for delivery (15 min to 35 days ahead).

    Returns:
        Twilio message SID on success, None on failure.
    """
    if not all(
        [
            TWILIO_ACCOUNT_SID,
            TWILIO_AUTH_TOKEN,
            TWILIO_MESSAGING_SERVICE_SID,
        ]
    ):
        logger.error(
            "Twilio credentials not configured -- check "
            "TWILIO_CONFIG (needs account_sid, auth_token, "
            "messaging_service_sid)"
        )
        return None

    try:
        from twilio.rest import Client as TwilioClient

        client = TwilioClient(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
        message = client.messages.create(
            messaging_service_sid=TWILIO_MESSAGING_SERVICE_SID,
            to=phone,
            body=body,
            schedule_type="fixed",
            send_at=send_at,
        )

        logger.info(
            "Scheduled SMS to %s (SID: %s, send_at: %s, status: %s)",
            phone[:2] + "***" + phone[-4:],
            message.sid,
            send_at.isoformat(),
            message.status,
        )
        return message.sid

    except Exception as e:
        logger.error(
            "Twilio scheduling failed for %s at %s: %s",
            phone[:2] + "***" + phone[-4:],
            send_at.isoformat(),
            e,
            exc_info=True,
        )
        return None


# -- BigQuery helpers ------------------------------------------------
def is_already_scheduled(client: bigquery.Client, response_id: str) -> bool:
    """Check whether follow-ups have already been scheduled.

    Queries the scheduled_followups table for rows with
    _scheduled=TRUE. Returns True if scheduling already
    completed, preventing duplicate messages on Pub/Sub
    redelivery.

    Args:
        client: BigQuery client.
        response_id: Qualtrics response ID to check.

    Returns:
        True if already scheduled, False otherwise.
    """
    full_table_id = (
        f"{config.gcp.project_id}.{config.bq.dataset_id}"
        f".{config.bq.tables.scheduled_followups}"
    )

    query = f"""
        SELECT 1
        FROM `{full_table_id}`
        WHERE response_id = @response_id
          AND _scheduled = TRUE
        LIMIT 1
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("response_id", "STRING", response_id)
        ]
    )

    rows = list(client.query(query, job_config=job_config).result())
    return len(rows) > 0


def write_scheduling_records(
    client: bigquery.Client,
    response_id: str,
    prolific_pid: str | None,
    phone: str,
    selected_date: str,
    timezone: str,
    scheduled_records: list[dict],
) -> bool:
    """Write scheduling records to BigQuery.

    Inserts one row per scheduled SMS (3 per participant)
    with the Twilio message SID for potential cancellation.
    All rows for a response_id are written atomically.

    Args:
        client: BigQuery client.
        response_id: Qualtrics response ID.
        prolific_pid: Prolific PID (nullable).
        phone: E.164 phone number.
        selected_date: ISO date string.
        timezone: IANA timezone.
        scheduled_records: List of dicts with keys: survey_time,
            twilio_sid, send_at_utc, survey_url.

    Returns:
        True if insert succeeded, False otherwise.
    """
    full_table_id = (
        f"{config.gcp.project_id}.{config.bq.dataset_id}"
        f".{config.bq.tables.scheduled_followups}"
    )

    now_utc = datetime.now(UTC).isoformat()
    rows = []
    for record in scheduled_records:
        rows.append(
            {
                "response_id": response_id,
                "prolific_pid": prolific_pid,
                "phone": phone,
                "selected_date": selected_date,
                "timezone": timezone,
                "survey_time": record["survey_time"],
                "twilio_message_sid": record["twilio_sid"],
                "send_at_utc": record["send_at_utc"],
                "survey_url": record["survey_url"],
                "_scheduled": True,
                "_created_at": now_utc,
            }
        )

    errors = client.insert_rows_json(full_table_id, rows)
    if errors:
        logger.error(
            "BigQuery insert errors for %s: %s",
            response_id,
            errors,
        )
        return False

    logger.info(
        "Wrote %d scheduling records for %s",
        len(rows),
        response_id,
    )
    return True


# -- Entry point -----------------------------------------------------
@functions_framework.cloud_event
def followup_scheduling_handler(cloud_event: CloudEvent) -> None:
    """Handle Pub/Sub messages for follow-up SMS scheduling.

    Decodes the message, verifies idempotency, builds survey URLs,
    schedules three SMS messages via Twilio, and writes audit
    records to BigQuery.

    If any Twilio scheduling call fails, the function raises an
    exception so Pub/Sub does not acknowledge the message and
    retries with exponential backoff.

    Args:
        cloud_event: CloudEvent containing the Pub/Sub message
            with FollowupSchedulingMessage data.
    """
    # Step 1: Decode the Pub/Sub message
    raw = decode_pubsub_message(cloud_event)
    if raw is None:
        logger.error("Could not decode message -- acknowledging to skip")
        return

    try:
        message = FollowupSchedulingMessage.model_validate(raw)
    except Exception as e:
        logger.error("Message validation failed: %s (data: %s)", e, raw)
        return

    logger.info(
        "Processing follow-up scheduling for response %s (phone: %s***%s)",
        message.response_id,
        message.phone[:2],
        message.phone[-4:],
    )

    # Step 2: Idempotency check
    bq_client = bigquery.Client(project=config.gcp.project_id)

    if is_already_scheduled(bq_client, message.response_id):
        logger.info(
            "Follow-ups already scheduled for %s -- skipping",
            message.response_id,
        )
        return

    # Step 3: Validate timezone
    try:
        zoneinfo.ZoneInfo(message.timezone)
    except KeyError:
        logger.error(
            "Unrecognized timezone '%s' for response %s -- "
            "cannot schedule. Acknowledging to prevent infinite retry.",
            message.timezone,
            message.response_id,
        )
        return

    # Step 4: Parse date and schedule all three SMS
    selected_date = date.fromisoformat(message.selected_date)
    survey_ids = config.followup_surveys.survey_ids
    sms_template = config.followup_surveys.sms_template

    scheduled_records: list[dict] = []
    for i, (survey_time, survey_id) in enumerate(
        zip(FOLLOWUP_TIMES, survey_ids)
    ):
        slot_number = i + 1

        url = build_survey_url(
            survey_id=survey_id,
            response_id=message.response_id,
            prolific_pid=message.prolific_pid,
            survey_time=slot_number,
            selected_date=message.selected_date,
        )

        if message.send_immediately:
            # Test mode: schedule at now + (slot * MIN_SCHEDULE_LEAD)
            # so all 3 arrive within ~48 min instead of waiting for
            # fixed study times (9/13/17 h) on a future date.
            now_utc = datetime.now(zoneinfo.ZoneInfo("UTC"))
            send_at = now_utc + MIN_SCHEDULE_LEAD * slot_number
            logger.info(
                "send_immediately=True: slot %d for %s scheduled at %s",
                slot_number,
                message.response_id,
                send_at.isoformat(),
            )
        else:
            send_at = compute_send_at(
                selected_date, survey_time, message.timezone
            )

            # Guard: skip slots that are too soon for Twilio scheduling
            now_utc = datetime.now(zoneinfo.ZoneInfo("UTC"))
            if send_at <= now_utc + MIN_SCHEDULE_LEAD:
                logger.warning(
                    "Skipping slot %d for %s -- send_at %s is less than "
                    "%d min from now (%s)",
                    slot_number,
                    message.response_id,
                    send_at.isoformat(),
                    int(MIN_SCHEDULE_LEAD.total_seconds() / 60),
                    now_utc.isoformat(),
                )
                continue

        time_label = format_time_label(survey_time)
        body = sms_template.format(time=time_label, url=url)

        twilio_sid = schedule_sms(message.phone, body, send_at)
        if twilio_sid is None:
            raise RuntimeError(
                f"Twilio scheduling failed for response "
                f"{message.response_id} slot {slot_number} -- "
                f"will retry via Pub/Sub"
            )

        scheduled_records.append(
            {
                "survey_time": slot_number,
                "twilio_sid": twilio_sid,
                "send_at_utc": send_at.isoformat(),
                "survey_url": url,
            }
        )

    # Guard: if all slots were skipped (all in the past), acknowledge
    # the message to prevent infinite Pub/Sub retry.
    if not scheduled_records:
        logger.error(
            "All 3 time slots are in the past for %s (date: %s, tz: %s) "
            "-- no SMS scheduled. Acknowledging to prevent infinite retry.",
            message.response_id,
            message.selected_date,
            message.timezone,
        )
        return

    # Step 5: Write scheduling records to BigQuery
    write_success = write_scheduling_records(
        bq_client,
        response_id=message.response_id,
        prolific_pid=message.prolific_pid,
        phone=message.phone,
        selected_date=message.selected_date,
        timezone=message.timezone,
        scheduled_records=scheduled_records,
    )

    if not write_success:
        # Do NOT raise -- SMS are already scheduled in Twilio.
        # A failed BQ write means the idempotency guard won't
        # prevent duplicates on retry, but an operational alert
        # should catch this. Duplicate SMS is preferable to
        # missed SMS for a research study.
        logger.warning(
            "Scheduling succeeded but BQ write failed for %s -- "
            "Twilio SIDs: %s",
            message.response_id,
            [r["twilio_sid"] for r in scheduled_records],
        )

    logger.info(
        "Follow-up scheduling complete for response %s (%d messages scheduled)",
        message.response_id,
        len(scheduled_records),
    )
