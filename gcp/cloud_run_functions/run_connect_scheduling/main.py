"""Cloud Function for CloudResearch Connect participant scheduling.

Triggered by Pub/Sub messages published by run-qualtrics-scheduling
when a Connect participant (32-hex connect_id) is detected. Sends an
immediate notification and schedules three follow-up survey messages
via the CloudResearch Connect API.

fn2 (run-intake-confirmation) and fn3 (run-followup-scheduling) are
bypassed entirely for Connect participants -- they have no usable phone
number and receive messages through the Connect platform instead.

Workflow:
    1. Decode and validate the Pub/Sub message
    2. Check idempotency (_processed flag in BigQuery)
    3. Per slot: check BQ sentinel, POST send-bulk-message, insert row
    4. Send notification if >= 1 slot scheduled
    5. Flip _processed=TRUE in stg_intake_responses

Idempotency:
    Handler-start guard: if _processed=TRUE in stg_intake_responses,
    ack immediately. Per-slot guard: BQ pre-check on
    twilio_message_sid='connect:<token>' before each Connect API call.
    Connect API IDEMPOTENCY-TOKEN header prevents double-sends even
    if BQ pre-check is bypassed during Pub/Sub redelivery.

Sentinel convention (matches backfill in scripts/send_connect_followups.py):
    phone='connect', twilio_message_sid='connect:{response_id}-{slot}-{date}'
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
from shared.utils.pubsub_utils import ConnectSchedulingMessage

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

# -- Connect API key (injected by Cloud Run via --set-secrets) -------
CONNECT_API_KEY: str = os.environ.get("CLOUDRESEARCH_CONNECT_API_KEY", "")

# Minimum lead before a scheduled delivery time (from config or default 30 min)
_lead_secs = config.connect.min_lead_seconds if config.connect else 1800
MIN_SCHEDULE_LEAD = timedelta(seconds=_lead_secs)


# -- Helpers ---------------------------------------------------------


def _connect_request(
    method: str,
    path: str,
    *,
    json_body: dict | None = None,
    params: dict | None = None,
    idempotency_token: str | None = None,
) -> object:
    """Make an authenticated Connect API request; raise on non-2xx.

    Lazily imports requests so the package is only required at runtime,
    not during test collection.

    Args:
        method: HTTP method (GET, POST, etc.).
        path: API path (e.g., '/api/v1/conversations/send-message').
        json_body: Request body as a dict, JSON-serialized automatically.
        params: Query parameters.
        idempotency_token: If set, added as IDEMPOTENCY-TOKEN header.

    Returns:
        requests.Response on success.

    Raises:
        requests.HTTPError: On non-2xx response.
    """
    import requests

    url = f"{config.connect.base_url}{path}"
    headers: dict[str, str] = {"X-API-KEY": CONNECT_API_KEY}
    if idempotency_token:
        headers["IDEMPOTENCY-TOKEN"] = idempotency_token
    resp = requests.request(
        method,
        url,
        headers=headers,
        json=json_body,
        params=params,
        timeout=30,
    )
    if not resp.ok:
        trace = resp.headers.get("X-TRACE-ID", "none")
        logger.error(
            "Connect API %s %s -> HTTP %d X-TRACE-ID=%s: %s",
            method,
            path,
            resp.status_code,
            trace,
            resp.text[:200],
        )
        resp.raise_for_status()
    return resp


def get_followup_times(work_shift: str | None) -> list[time]:
    """Return three delivery times for a participant's work shift.

    Args:
        work_shift: Shift label from the intake survey, or None to
            use the configured default.

    Returns:
        List of three time objects in the participant's local timezone.

    Raises:
        RuntimeError: If shift_times is absent from config.
        KeyError: If work_shift is not in config.shift_times.shifts.
    """
    if config.shift_times is None:
        raise RuntimeError("shift_times missing from connect config")
    shift_key = work_shift or config.shift_times.default_shift
    raw = config.shift_times.shifts[shift_key]
    return [time.fromisoformat(t) for t in raw]


def format_time_label(t: time) -> str:
    """Format a time object as a 12-hour string (e.g., '9:00 AM').

    Args:
        t: Time to format.

    Returns:
        Formatted time string.
    """
    period = "AM" if t.hour < 12 else "PM"
    display_hour = t.hour % 12 or 12
    return f"{display_hour}:{t.minute:02d} {period}"


def parse_date(val: object) -> date:
    """Coerce a BQ string or date value to a date object.

    Args:
        val: ISO date string, date, or datetime.

    Returns:
        date object.
    """
    if isinstance(val, datetime):
        return val.date()
    if isinstance(val, date):
        return val
    return date.fromisoformat(str(val))


def compute_send_at_utc(
    selected_date: date,
    survey_time: time,
    timezone_str: str,
) -> datetime:
    """Convert a local survey window time to UTC.

    Args:
        selected_date: Date for the follow-up survey.
        survey_time: Local time for delivery.
        timezone_str: IANA timezone string (e.g., US/Eastern).

    Returns:
        UTC datetime for the Connect API scheduledDelivery field.

    Raises:
        KeyError: If timezone_str is not recognized by zoneinfo.
    """
    tz = zoneinfo.ZoneInfo(timezone_str)
    local_dt = datetime.combine(selected_date, survey_time, tzinfo=tz)
    return local_dt.astimezone(zoneinfo.ZoneInfo("UTC"))


def build_survey_url(
    survey_id: str,
    response_id: str,
    connect_id: str,
    survey_time: int,
    selected_date_str: str,
) -> str:
    """Build a Qualtrics follow-up survey URL with embedded metadata.

    Args:
        survey_id: Qualtrics survey ID for this time slot.
        response_id: Original intake response ID.
        connect_id: Connect participant ID.
        survey_time: Time slot number (1, 2, or 3).
        selected_date_str: ISO date string (YYYY-MM-DD).

    Returns:
        Complete URL with query parameters.
    """
    params: dict[str, str | int] = {
        "response_id": response_id,
        "survey_time": survey_time,
        "selected_date": selected_date_str,
        "connect_id": connect_id,
    }
    return f"{config.connect.survey_base_url}/{survey_id}?{urlencode(params)}"


def make_idempotency_token(
    response_id: str,
    survey_slot: int,
    selected_date_str: str,
) -> str:
    """Build a deterministic idempotency token to prevent double-sends.

    Matches the backfill convention in scripts/send_connect_followups.py
    so backfill rows and pipeline rows share the same idempotency namespace.

    Args:
        response_id: Qualtrics response ID.
        survey_slot: Slot number (1, 2, or 3).
        selected_date_str: ISO date string (YYYY-MM-DD).

    Returns:
        Token string used in IDEMPOTENCY-TOKEN header and BQ sentinel.
    """
    return f"{response_id}-{survey_slot}-{selected_date_str}"


def render_notification(
    work_shift: str | None,
    selected_date: date,
    timezone_str: str,
) -> str:
    """Render the upfront notification message body for a participant.

    Args:
        work_shift: Shift label for delivery time windows.
        selected_date: Survey date to display.
        timezone_str: IANA timezone label for display.

    Returns:
        Rendered notification message body.
    """
    windows = get_followup_times(work_shift)
    labels = [format_time_label(t) for t in windows]
    date_long = selected_date.strftime("%A, %B %d, %Y")
    return config.connect.notification_template.format(
        selected_date_long=date_long,
        window_1=labels[0],
        window_2=labels[1],
        window_3=labels[2],
        timezone_label=timezone_str,
    )


# -- BQ helpers -------------------------------------------------------


def decode_pubsub_message(cloud_event: CloudEvent) -> dict | None:
    """Decode and parse a Pub/Sub message from a CloudEvent.

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
    """Check whether a response has _processed=TRUE in stg_intake_responses.

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
            "No intake row found for response %s -- may be in streaming buffer",
            response_id,
        )
        return False
    return bool(rows[0]._processed)


def slot_already_scheduled(
    client: bigquery.Client, idempotency_token: str
) -> bool:
    """Check whether a slot is already in scheduled_followups.

    Uses the twilio_message_sid sentinel 'connect:<token>' as the
    idempotency key. Returns True if the slot was already written,
    so it is safe to skip the Connect API call.

    Args:
        client: BigQuery client.
        idempotency_token: Token in the format response_id-slot-date.

    Returns:
        True if the slot row exists, False otherwise.
    """
    full_table_id = (
        f"{config.gcp.project_id}.{config.bq.dataset_id}"
        f".{config.bq.tables.scheduled_followups}"
    )
    sentinel = f"connect:{idempotency_token}"
    query = f"""
        SELECT 1
        FROM `{full_table_id}`
        WHERE twilio_message_sid = @sentinel
        LIMIT 1
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("sentinel", "STRING", sentinel)
        ]
    )
    rows = list(client.query(query, job_config=job_config).result())
    return len(rows) > 0


def insert_scheduling_record(
    client: bigquery.Client,
    response_id: str,
    connect_id: str,
    selected_date_str: str,
    timezone_str: str,
    survey_time_slot: int,
    idempotency_token: str,
    send_at_utc: datetime,
    survey_url: str,
) -> bool:
    """Insert one scheduling record into scheduled_followups.

    Uses phone='connect' and twilio_message_sid='connect:<token>' as
    sentinels to distinguish Connect rows from Twilio rows. This matches
    the backfill convention in scripts/send_connect_followups.py.

    Args:
        client: BigQuery client.
        response_id: Qualtrics response ID.
        connect_id: Connect participant ID.
        selected_date_str: ISO date string.
        timezone_str: IANA timezone string.
        survey_time_slot: Slot number (1, 2, or 3).
        idempotency_token: Token for the sentinel twilio_message_sid.
        send_at_utc: Scheduled delivery UTC datetime.
        survey_url: Qualtrics follow-up survey URL.

    Returns:
        True if the insert succeeded, False otherwise.
    """
    full_table_id = (
        f"{config.gcp.project_id}.{config.bq.dataset_id}"
        f".{config.bq.tables.scheduled_followups}"
    )
    row = {
        "response_id": response_id,
        "connect_id": connect_id,
        "phone": "connect",
        "selected_date": selected_date_str,
        "timezone": timezone_str,
        "survey_time": survey_time_slot,
        "twilio_message_sid": f"connect:{idempotency_token}",
        "send_at_utc": send_at_utc.isoformat(),
        "survey_url": survey_url,
        "_scheduled": True,
        "_created_at": datetime.now(UTC).isoformat(),
    }
    errors = client.insert_rows_json(full_table_id, [row])
    if errors:
        logger.error(
            "BigQuery insert error for %s slot %d: %s",
            response_id,
            survey_time_slot,
            errors,
        )
        return False
    logger.info(
        "Inserted scheduling record for %s slot %d",
        response_id,
        survey_time_slot,
    )
    return True


def update_processed_flag(client: bigquery.Client, response_id: str) -> bool:
    """Set _processed=TRUE in stg_intake_responses.

    Uses a WHERE _processed=FALSE guard for safety.

    Args:
        client: BigQuery client.
        response_id: Qualtrics response ID.

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
        job = client.query(query, job_config=job_config)
        job.result()
        logger.info("Flipped _processed=TRUE for %s", response_id)
        return True
    except Exception as e:
        logger.error(
            "Failed to update _processed for %s: %s",
            response_id,
            e,
            exc_info=True,
        )
        return False


# -- Entry point -------------------------------------------------------


@functions_framework.cloud_event
def connect_scheduling_handler(cloud_event: CloudEvent) -> None:
    """Handle Pub/Sub messages for CloudResearch Connect scheduling.

    Decodes the message, verifies idempotency, schedules three follow-up
    survey messages via the Connect API, sends a notification, and flips
    _processed=TRUE.

    Raises on slot send failure so Pub/Sub retries. Per-slot BQ pre-check
    and IDEMPOTENCY-TOKEN header prevent double-sends on retry.

    Args:
        cloud_event: CloudEvent containing ConnectSchedulingMessage data.
    """
    # Step 1: Decode and validate Pub/Sub message
    raw = decode_pubsub_message(cloud_event)
    if raw is None:
        logger.error("Could not decode message -- acknowledging to skip")
        return

    try:
        message = ConnectSchedulingMessage.model_validate(raw)
    except Exception as e:
        logger.error("Message validation failed: %s (data: %s)", e, raw)
        return

    logger.info(
        "Processing Connect scheduling for response %s (connect_id: %s)",
        message.response_id,
        message.connect_id,
    )

    # Step 2: Validate timezone and date before hitting BQ
    try:
        zoneinfo.ZoneInfo(message.timezone)
    except KeyError:
        logger.error(
            "Unrecognized timezone '%s' for %s -- ack to prevent retry loop",
            message.timezone,
            message.response_id,
        )
        return

    try:
        selected_date = date.fromisoformat(message.selected_date)
    except ValueError:
        logger.error(
            "Invalid date '%s' for %s -- ack to prevent retry loop",
            message.selected_date,
            message.response_id,
        )
        return

    # Step 3: Idempotency guard -- ack immediately if already processed
    bq_client = bigquery.Client(project=config.gcp.project_id)

    if is_already_processed(bq_client, message.response_id):
        logger.info(
            "Response %s already processed -- skipping",
            message.response_id,
        )
        return

    # Step 4: Per-slot scheduling
    try:
        followup_times = get_followup_times(message.work_shift)
    except KeyError:
        logger.exception(
            "Unknown work_shift '%s' for %s -- ack to prevent retry loop",
            message.work_shift,
            message.response_id,
        )
        return

    if not config.connect:
        logger.error("connect config missing -- cannot schedule")
        return

    survey_ids = config.connect.survey_ids
    slots_scheduled = 0

    for i, (survey_time, survey_id) in enumerate(
        zip(followup_times, survey_ids, strict=True)
    ):
        slot_number = i + 1
        token = make_idempotency_token(
            message.response_id, slot_number, message.selected_date
        )

        if message.send_immediately:
            now_utc = datetime.now(zoneinfo.ZoneInfo("UTC"))
            send_at = now_utc + MIN_SCHEDULE_LEAD * slot_number
            logger.info(
                "send_immediately=True: slot %d for %s at %s",
                slot_number,
                message.response_id,
                send_at.isoformat(),
            )
        else:
            send_at = compute_send_at_utc(
                selected_date, survey_time, message.timezone
            )
            now_utc = datetime.now(zoneinfo.ZoneInfo("UTC"))
            if send_at <= now_utc + MIN_SCHEDULE_LEAD:
                logger.warning(
                    "Skipping slot %d for %s -- send_at %s within lead window",
                    slot_number,
                    message.response_id,
                    send_at.isoformat(),
                )
                continue

        # BQ pre-check: skip if already recorded (retry safety)
        if slot_already_scheduled(bq_client, token):
            logger.info(
                "Slot %d for %s already in BQ -- skipping send",
                slot_number,
                message.response_id,
            )
            slots_scheduled += 1
            continue

        url = build_survey_url(
            survey_id=survey_id,
            response_id=message.response_id,
            connect_id=message.connect_id,
            survey_time=slot_number,
            selected_date_str=message.selected_date,
        )
        time_label = format_time_label(survey_time)
        msg_body = config.connect.survey_message_template.format(
            time=time_label, url=url
        )

        # POST send-bulk-message (raises on failure -> Pub/Sub retries)
        _connect_request(
            "POST",
            "/api/v1/conversations/send-bulk-message",
            json_body={
                "participantIds": [message.connect_id],
                "projectId": config.connect.cloudresearch_project_id,
                "message": msg_body,
                "subject": f"slot-{slot_number} follow-up survey",
                "scheduledDelivery": send_at.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
            },
            idempotency_token=token,
        )

        # BQ insert (warn on failure; don't raise -- send already happened)
        ok = insert_scheduling_record(
            bq_client,
            response_id=message.response_id,
            connect_id=message.connect_id,
            selected_date_str=message.selected_date,
            timezone_str=message.timezone,
            survey_time_slot=slot_number,
            idempotency_token=token,
            send_at_utc=send_at,
            survey_url=url,
        )
        if not ok:
            logger.warning(
                "Connect send succeeded but BQ write failed for %s slot %d "
                "(token: %s)",
                message.response_id,
                slot_number,
                token,
            )

        slots_scheduled += 1

    # Step 5: Notification (only if >= 1 slot was scheduled)
    if slots_scheduled == 0:
        logger.error(
            "All slots past lead window for %s (date: %s, tz: %s) -- "
            "no sends. Leaving _processed=FALSE for visibility.",
            message.response_id,
            message.selected_date,
            message.timezone,
        )
        return

    notification_body = render_notification(
        message.work_shift, selected_date, message.timezone
    )
    try:
        _connect_request(
            "POST",
            "/api/v1/conversations/send-message",
            json_body={
                "recipientId": message.connect_id,
                "projectId": config.connect.cloudresearch_project_id,
                "message": notification_body,
                "subject": "Your follow-up surveys for the work experiences study",
            },
        )
        logger.info(
            "Sent notification to %s for response %s",
            message.connect_id,
            message.response_id,
        )
    except Exception as e:
        # Notification failure is non-fatal -- slots are already scheduled.
        # Participant will still receive survey links even without the
        # advance notification.
        logger.warning(
            "Notification send failed for %s: %s -- continuing to _processed flip",
            message.response_id,
            e,
        )

    # Step 6: Flip _processed=TRUE
    updated = update_processed_flag(bq_client, message.response_id)
    if not updated:
        logger.warning(
            "Scheduling complete but _processed flip failed for %s -- "
            "Pub/Sub redelivery will ack at step 3 next time",
            message.response_id,
        )

    logger.info(
        "Connect scheduling complete for %s (%d slots scheduled)",
        message.response_id,
        slots_scheduled,
    )
