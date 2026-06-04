"""Deliver CloudResearch follow-up survey links via the Connect API.

Replaces the Twilio SMS pipeline for the 18 CloudResearch participants
(enrolled 2026-06-03) who provided fake phone numbers. Sends study
follow-up survey links via connect_id using the CloudResearch Connect API.

Requires CLOUDRESEARCH_CONNECT_API_KEY and CLOUDRESEARCH_PROJECT_ID in the
environment. Source ~/.bashrc before running to load these from
~/.bashrc.local.

Run in order:
    # Smoke test auth and BQ counts
    source ~/.bashrc && uv run python scripts/send_connect_followups.py \\
        --phase verify [--dry-run]

    # Reschedule 2 participants whose selected_date (2026-06-04) has passed
    source ~/.bashrc && uv run python scripts/send_connect_followups.py \\
        --phase reschedule [--dry-run]

    # Send upfront notification to all 18 (review dry-run first)
    source ~/.bashrc && uv run python scripts/send_connect_followups.py \\
        --phase notify --dry-run
    source ~/.bashrc && uv run python scripts/send_connect_followups.py \\
        --phase notify

    # Schedule 54 follow-up survey messages (3 per participant)
    source ~/.bashrc && uv run python scripts/send_connect_followups.py \\
        --phase schedule --dry-run
    source ~/.bashrc && uv run python scripts/send_connect_followups.py \\
        --phase schedule

    # Final verification
    source ~/.bashrc && uv run python scripts/send_connect_followups.py \\
        --phase verify

Target a subset:
    source ~/.bashrc && uv run python scripts/send_connect_followups.py \\
        --phase notify --response-ids R_abc123,R_def456 --dry-run
"""

from __future__ import annotations

import argparse
import os
import sys
import time as time_mod
from datetime import date, datetime, time, timezone
from typing import Any
from urllib.parse import urlencode
import zoneinfo

import requests
from google.cloud import bigquery

# ---- Constants -------------------------------------------------------

CONNECT_BASE_URL = "https://connect-api.cloudresearch.com"
BQ_PROJECT = "dkg-phd-thesis"
BQ_DATASET = "qualtrics"
BASE_SURVEY_URL = "https://ncsu.qualtrics.com/jfe/form"
SURVEY_IDS = [
    "SV_5nV942MJGubDmqq",  # slot 1 (first window)
    "SV_eRKl4lgMZDAurT8",  # slot 2 (second window)
    "SV_6J3svun1r97AAHc",  # slot 3 (third window)
]
EXPECTED_PARTICIPANT_COUNT = 18

# Window times per shift (from configs/gcp_utils.yaml shift_times.shifts)
SHIFT_TIMES: dict[str, list[str]] = {
    "early_shift": ["06:00", "08:45", "11:30"],
    "first_shift": ["09:00", "13:00", "17:00"],
    "second_shift": ["16:00", "19:00", "22:00"],
    "third_shift": ["01:00", "04:00", "07:00"],
}
DEFAULT_SHIFT = "first_shift"

# Two participants whose selected_date (2026-06-04) has passed
RESCHEDULE_IDS = ["R_11GInvmIGUavxnm", "R_3zROuLfghaRvtjM"]
RESCHEDULE_NEW_DATE = "2026-06-05"

# Minimum scheduling lead time before a window is skipped (30 minutes)
MIN_LEAD_SECONDS = 30 * 60

# ---- Message templates -----------------------------------------------

NOTIFICATION_SUBJECT = "Your follow-up surveys for the work experiences study"

NOTIFICATION_TEMPLATE = (
    "Hello, this is Demetrius K. Green, the researcher for the work "
    "experiences study you recently completed the intake survey for. "
    "A quick update on how your follow-up surveys will reach you.\n\n"
    "Your three follow-up survey links will be delivered here in Connect, "
    "through this conversation, rather than by text message. We understand "
    "that many Connect participants prefer not to share a personal phone "
    "number, and that is completely fine. No phone number is needed; "
    "everything for this study will come through Connect from now on.\n\n"
    "{reschedule_note}"
    "On {selected_date_long}, you will receive three separate messages here, "
    "one for each follow-up survey, at approximately {window_1}, {window_2}, "
    "and {window_3} ({timezone_label}). Please complete each survey within "
    "1 hour of receiving it for your responses to be valid.\n\n"
    "Compensation is unchanged. Thank you for being part of this research; "
    "your responses are genuinely valuable. If you have any questions, just "
    "reply to this message."
)

RESCHEDULE_NOTE = (
    "Your originally selected day has passed, so your follow-up surveys "
    "have been rescheduled. "
)

SURVEY_SUBJECT_TEMPLATE = "{time} follow-up survey"

SURVEY_MESSAGE_TEMPLATE = (
    "Hello, this is Demetrius K. Green. It is time for your "
    "{time} follow-up survey for the research study. Please "
    "complete it within 1 hour for your response to be valid: {url}"
)


# ---- Env loading -----------------------------------------------------


def _load_env() -> tuple[str, str]:
    """Load Connect API key and project ID from environment."""
    api_key = os.environ.get("CLOUDRESEARCH_CONNECT_API_KEY", "")
    project_id = os.environ.get("CLOUDRESEARCH_PROJECT_ID", "")
    if not api_key:
        print(
            "ERROR: CLOUDRESEARCH_CONNECT_API_KEY not set.\n"
            "Run: source ~/.bashrc && uv run python "
            "scripts/send_connect_followups.py ..."
        )
        sys.exit(1)
    if not project_id:
        print("ERROR: CLOUDRESEARCH_PROJECT_ID not set.")
        sys.exit(1)
    return api_key, project_id


# ---- Connect API client ----------------------------------------------


def _connect_request(
    method: str,
    path: str,
    api_key: str,
    *,
    json_body: dict[str, Any] | None = None,
    params: dict[str, Any] | None = None,
    idempotency_token: str | None = None,
) -> requests.Response:
    """Make an authenticated Connect API request; raise on non-2xx."""
    url = f"{CONNECT_BASE_URL}{path}"
    headers: dict[str, str] = {"X-API-KEY": api_key}
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
        print(
            f"  Connect API {method} {path} -> HTTP {resp.status_code} "
            f"X-TRACE-ID={trace}: {resp.text[:200]}"
        )
        resp.raise_for_status()
    return resp


# ---- Pure helpers (unit-testable) ------------------------------------


def get_shift_times(work_shift: str | None) -> list[time]:
    """Return three delivery time objects for a participant's shift."""
    key = work_shift if work_shift in SHIFT_TIMES else DEFAULT_SHIFT
    return [time.fromisoformat(t) for t in SHIFT_TIMES[key]]


def format_time_label(t: time) -> str:
    """Format a time object as a 12-hour label, e.g. '9:00 AM'."""
    period = "AM" if t.hour < 12 else "PM"
    display_hour = t.hour % 12 or 12
    return f"{display_hour}:{t.minute:02d} {period}"


def parse_date(val: Any) -> date:
    """Coerce a BQ string or date value to a date object."""
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
    """Convert a local survey window time to UTC."""
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
    """Build a Qualtrics follow-up survey URL with embedded metadata."""
    params: dict[str, Any] = {
        "response_id": response_id,
        "survey_time": survey_time,
        "selected_date": selected_date_str,
        "connect_id": connect_id,
    }
    return f"{BASE_SURVEY_URL}/{survey_id}?{urlencode(params)}"


def make_idempotency_token(
    response_id: str,
    survey_slot: int,
    selected_date_str: str,
) -> str:
    """Build a deterministic idempotency token to prevent double-sends."""
    return f"{response_id}-{survey_slot}-{selected_date_str}"


def render_notification(
    row: dict[str, Any],
    selected_date: date,
    is_rescheduled: bool,
) -> str:
    """Render the upfront notification message body for a participant."""
    windows = get_shift_times(row.get("work_shift"))
    labels = [format_time_label(t) for t in windows]
    date_long = selected_date.strftime("%A, %B %d, %Y")
    reschedule_note = RESCHEDULE_NOTE if is_rescheduled else ""
    return NOTIFICATION_TEMPLATE.format(
        reschedule_note=reschedule_note,
        selected_date_long=date_long,
        window_1=labels[0],
        window_2=labels[1],
        window_3=labels[2],
        timezone_label=row["timezone"],
    )


# ---- BQ helpers ------------------------------------------------------

PARTICIPANT_QUERY_BASE = """
    select
        response_id,
        connect_id,
        selected_date,
        timezone,
        work_shift
    from `dkg-phd-thesis.qualtrics.stg_intake_responses`
    where
        _processed = false
        and regexp_contains(connect_id, r'^[0-9A-Fa-f]{{32}}$')
"""


def query_participants(
    bq: bigquery.Client,
    response_ids: list[str] | None,
) -> list[dict[str, Any]]:
    """Query stg_intake_responses for the CloudResearch cohort."""
    if response_ids:
        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ArrayQueryParameter("ids", "STRING", response_ids),
            ]
        )
        sql = (
            PARTICIPANT_QUERY_BASE.format()
            + " and response_id in unnest(@ids) order by response_id"
        )
        rows = list(bq.query(sql, job_config=job_config).result())
    else:
        sql = (
            PARTICIPANT_QUERY_BASE.format()
            + " order by selected_date, response_id"
        )
        rows = list(bq.query(sql).result())
    return [dict(r) for r in rows]


# ---- Phase: verify ---------------------------------------------------


def phase_verify(
    bq: bigquery.Client,
    api_key: str,
    dry_run: bool,
) -> None:
    print("Phase: verify\n")

    if dry_run:
        print(
            "  [DRY RUN] Would GET "
            "/api/v1/conversations/bulk-messages?Mailbox=Scheduled"
        )
    else:
        print("  GET /api/v1/conversations/bulk-messages?Mailbox=Scheduled ...")
        resp = _connect_request(
            "GET",
            "/api/v1/conversations/bulk-messages",
            api_key,
            params={"Mailbox": "Scheduled", "Size": 1},
        )
        print(f"  Connect API: HTTP {resp.status_code} (auth OK)")

    counts_sql = """
        select
          (
            select count(*)
            from `dkg-phd-thesis.qualtrics.stg_intake_responses`
            where
                _processed = false
                and regexp_contains(connect_id, r'^[0-9A-Fa-f]{32}$')
          ) as unprocessed,
          (
            select count(*)
            from `dkg-phd-thesis.qualtrics.stg_intake_responses`
            where
                _processed = true
                and regexp_contains(connect_id, r'^[0-9A-Fa-f]{32}$')
          ) as processed,
          (
            select count(*)
            from `dkg-phd-thesis.qualtrics.scheduled_followups`
            where
                regexp_contains(
                    coalesce(connect_id, ''), r'^[0-9A-Fa-f]{32}$'
                )
                and starts_with(twilio_message_sid, 'connect:')
          ) as connect_followups
    """
    row = list(bq.query(counts_sql).result())[0]
    print(
        f"\n  BQ counts:"
        f"\n    unprocessed (connect cohort) : {row.unprocessed}"
        f"\n    processed   (connect cohort) : {row.processed}"
        f"\n    scheduled_followups (connect): {row.connect_followups}"
        f"\n\n  Expected after full run:"
        f"\n    unprocessed=0, processed=18, connect_followups=54"
    )


# ---- Phase: reschedule -----------------------------------------------


def phase_reschedule(
    bq: bigquery.Client,
    dry_run: bool,
    response_ids: list[str] | None,
) -> None:
    print("Phase: reschedule\n")

    target_ids = RESCHEDULE_IDS
    if response_ids:
        target_ids = [r for r in RESCHEDULE_IDS if r in response_ids]
        if not target_ids:
            print(
                "  No RESCHEDULE_IDS in --response-ids filter; nothing to do."
            )
            return

    print(f"  Updating {target_ids}")
    print(f"  -> selected_date = {RESCHEDULE_NEW_DATE}\n")

    update_sql = f"""
        update `{BQ_PROJECT}.{BQ_DATASET}.stg_intake_responses`
        set selected_date = '{RESCHEDULE_NEW_DATE}'
        where response_id in unnest(@ids)
          and _processed = false
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ArrayQueryParameter("ids", "STRING", target_ids),
        ]
    )
    if dry_run:
        print(f"  [DRY RUN] Would UPDATE {len(target_ids)} row(s):")
        print(f"  {update_sql.strip()}")
    else:
        job = bq.query(update_sql, job_config=job_config)
        job.result()
        print(f"  UPDATE: {job.num_dml_affected_rows} rows affected")
        verify_sql = """
            select response_id, selected_date
            from `dkg-phd-thesis.qualtrics.stg_intake_responses`
            where response_id in unnest(@ids)
        """
        for r in bq.query(verify_sql, job_config=job_config).result():
            print(f"    {r.response_id}: selected_date={r.selected_date}")


# ---- Phase: notify ---------------------------------------------------


def phase_notify(
    bq: bigquery.Client,
    api_key: str,
    project_id: str,
    dry_run: bool,
    response_ids: list[str] | None,
) -> None:
    print("Phase: notify\n")

    rows = query_participants(bq, response_ids)
    if not rows:
        print("  No participants found; nothing to do.")
        return

    if not response_ids and len(rows) != EXPECTED_PARTICIPANT_COUNT:
        print(
            f"  WARNING: expected {EXPECTED_PARTICIPANT_COUNT} participants, "
            f"found {len(rows)}."
        )
        for r in rows:
            print(
                f"    {r['response_id']}: date={r['selected_date']} "
                f"tz={r['timezone']} shift={r.get('work_shift')!r}"
            )
        if not dry_run:
            answer = input("\n  Proceed anyway? [y/N] ").strip().lower()
            if answer != "y":
                print("  Aborted.")
                sys.exit(1)

    success = 0
    failed: list[str] = []

    for r in rows:
        rid = r["response_id"]
        connect_id = r["connect_id"]
        selected_date = parse_date(r["selected_date"])
        is_rescheduled = rid in RESCHEDULE_IDS
        body = render_notification(r, selected_date, is_rescheduled)

        if dry_run:
            print(
                f"  [DRY RUN] {rid} ({connect_id[:8]}...) "
                f"rescheduled={is_rescheduled}"
            )
            print(f"  Subject: {NOTIFICATION_SUBJECT}")
            print(f"  Body:\n{body}\n")
            success += 1
            continue

        try:
            _connect_request(
                "POST",
                "/api/v1/conversations/send-message",
                api_key,
                json_body={
                    "projectId": project_id,
                    "subject": NOTIFICATION_SUBJECT,
                    "message": body,
                    "recipientId": connect_id,
                },
            )
            print(f"  OK   {rid} ({connect_id[:8]}...)")
            success += 1
        except Exception as e:
            print(f"  FAIL {rid}: {e}")
            failed.append(rid)
        time_mod.sleep(0.5)

    print(f"\n  {success} sent, {len(failed)} failed")
    if failed:
        print(f"  Failed: {failed}")
        sys.exit(1)


# ---- Phase: schedule -------------------------------------------------


def phase_schedule(
    bq: bigquery.Client,
    api_key: str,
    project_id: str,
    dry_run: bool,
    response_ids: list[str] | None,
) -> None:
    print("Phase: schedule\n")

    rows = query_participants(bq, response_ids)
    if not rows:
        print("  No participants found; nothing to do.")
        return

    if not response_ids and len(rows) != EXPECTED_PARTICIPANT_COUNT:
        print(
            f"  WARNING: expected {EXPECTED_PARTICIPANT_COUNT} participants, "
            f"found {len(rows)}."
        )
        if not dry_run:
            answer = input("  Proceed anyway? [y/N] ").strip().lower()
            if answer != "y":
                print("  Aborted.")
                sys.exit(1)

    now_utc = datetime.now(tz=timezone.utc)
    total_success = 0
    total_failed: list[str] = []

    for r in rows:
        rid = r["response_id"]
        connect_id = r["connect_id"]
        selected_date = parse_date(r["selected_date"])
        selected_date_str = selected_date.isoformat()
        shift_windows = get_shift_times(r.get("work_shift"))

        participant_ok = True
        scheduled_slots: list[int] = []

        for slot_idx, window_time in enumerate(shift_windows):
            slot = slot_idx + 1
            send_at = compute_send_at_utc(
                selected_date, window_time, r["timezone"]
            )
            lead_secs = (send_at - now_utc).total_seconds()
            if lead_secs <= MIN_LEAD_SECONDS:
                print(
                    f"  SKIP {rid} slot {slot}: "
                    f"{window_time.isoformat()} ({send_at.isoformat()}) "
                    f"within {MIN_LEAD_SECONDS // 60}min or past"
                )
                continue

            survey_id = SURVEY_IDS[slot_idx]
            url = build_survey_url(
                survey_id, rid, connect_id, slot, selected_date_str
            )
            time_label = format_time_label(window_time)
            message_body = SURVEY_MESSAGE_TEMPLATE.format(
                time=time_label, url=url
            )
            subject = SURVEY_SUBJECT_TEMPLATE.format(time=time_label)
            idempotency = make_idempotency_token(rid, slot, selected_date_str)
            send_at_iso = send_at.strftime("%Y-%m-%dT%H:%M:%SZ")

            if dry_run:
                print(
                    f"  [DRY RUN] {rid} slot {slot}: "
                    f"{send_at_iso} ({time_label})"
                )
                print(f"    idempotency: {idempotency}")
                print(f"    message: {message_body[:80]}...")
                scheduled_slots.append(slot)
                continue

            try:
                sid_value = f"connect:{idempotency}"
                already_row = list(
                    bq.query(
                        f"select 1 from `{BQ_PROJECT}.{BQ_DATASET}.scheduled_followups`"
                        f" where twilio_message_sid = '{sid_value}' limit 1"
                    ).result()
                )
                if already_row:
                    print(
                        f"  SKIP {rid} slot {slot}: BQ record exists, "
                        f"Connect send already recorded"
                    )
                    scheduled_slots.append(slot)
                    total_success += 1
                    continue

                _connect_request(
                    "POST",
                    "/api/v1/conversations/send-bulk-message",
                    api_key,
                    json_body={
                        "projectId": project_id,
                        "subject": subject,
                        "message": message_body,
                        "participantIds": [connect_id],
                        "scheduledDelivery": send_at_iso,
                    },
                    idempotency_token=idempotency,
                )
                print(f"  OK   {rid} slot {slot}: {send_at_iso} ({time_label})")

                send_at_bq = send_at.strftime("%Y-%m-%d %H:%M:%S")
                insert_sql = f"""
                    insert into
                        `{BQ_PROJECT}.{BQ_DATASET}.scheduled_followups`
                    (
                        response_id, connect_id, phone, selected_date,
                        timezone, survey_time, twilio_message_sid,
                        send_at_utc, survey_url, _scheduled, _created_at
                    )
                    values (
                        '{rid}',
                        '{connect_id}',
                        'connect',
                        '{selected_date_str}',
                        '{r["timezone"]}',
                        {slot},
                        '{sid_value}',
                        '{send_at_bq}',
                        '{url}',
                        true,
                        current_timestamp()
                    )
                """
                bq.query(insert_sql).result()
                print(f"       BQ insert OK slot {slot}")
                scheduled_slots.append(slot)
                total_success += 1

            except Exception as e:
                print(f"  FAIL {rid} slot {slot}: {e}")
                total_failed.append(f"{rid}-slot{slot}")
                participant_ok = False

            time_mod.sleep(0.25)

        if not dry_run and participant_ok and scheduled_slots:
            flip_sql = f"""
                update `{BQ_PROJECT}.{BQ_DATASET}.stg_intake_responses`
                set _processed = true
                where response_id = '{rid}'
            """
            bq.query(flip_sql).result()
            print(f"       _processed=TRUE for {rid}\n")
        elif not dry_run and not scheduled_slots:
            print(f"  {rid}: all windows skipped; leaving _processed=FALSE\n")

    if dry_run:
        print("\n  [DRY RUN] Reviewed schedule phase; no sends or BQ writes")
    else:
        print(f"\n  {total_success} scheduled, {len(total_failed)} failed")
        if total_failed:
            print(f"  Failed: {total_failed}")
            sys.exit(1)


# ---- CLI -------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--phase",
        required=True,
        choices=["verify", "reschedule", "notify", "schedule"],
        help="Phase to execute",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print all payloads without sending or writing",
    )
    parser.add_argument(
        "--response-ids",
        help=(
            "Comma-separated response_ids to target "
            "(default: all unprocessed connect participants)"
        ),
    )
    args = parser.parse_args()

    response_ids: list[str] | None = None
    if args.response_ids:
        response_ids = [
            r.strip() for r in args.response_ids.split(",") if r.strip()
        ]

    api_key, project_id = _load_env()
    bq = bigquery.Client(project=BQ_PROJECT)

    mode = "DRY RUN" if args.dry_run else "LIVE"
    print(f"\n{'=' * 60}")
    print(f"send_connect_followups -- phase={args.phase} -- {mode}")
    print(f"{'=' * 60}\n")

    if args.phase == "verify":
        phase_verify(bq, api_key, args.dry_run)
    elif args.phase == "reschedule":
        phase_reschedule(bq, args.dry_run, response_ids)
    elif args.phase == "notify":
        phase_notify(bq, api_key, project_id, args.dry_run, response_ids)
    elif args.phase == "schedule":
        phase_schedule(bq, api_key, project_id, args.dry_run, response_ids)

    print(f"\n{'=' * 60}")
    print(f"Done ({mode})")
    print(f"{'=' * 60}\n")


if __name__ == "__main__":
    main()
