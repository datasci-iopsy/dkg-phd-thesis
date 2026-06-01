"""Remediation script for shift scheduling mismatch (2026-06-01 incident).

Scope:
- Cancel 6 wrong Twilio messages for 2 second_shift participants
- Update stg_intake_responses: set work_shift/work_classification for all 5
  null-shift participants (3 first_shift, 2 second_shift)
- Schedule 6 new Twilio messages at correct second_shift UTC times
- Replace scheduled_followups rows for the 2 second_shift participants

Run:
    DRY_RUN=1 uv run python scripts/remediate_shift_scheduling.py
    uv run python scripts/remediate_shift_scheduling.py
"""

import json
import os
import sys
from datetime import datetime

import zoneinfo
from cryptography.fernet import Fernet
from google.cloud import bigquery
from twilio.rest import Client as TwilioClient

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEYS_DIR = os.path.join(PROJECT_ROOT, ".keys")

DRY_RUN = os.environ.get("DRY_RUN", "0") == "1"

# ---- Credentials -------------------------------------------------------

with open(os.path.join(KEYS_DIR, "twilio-config.json")) as f:
    twilio_cfg = json.load(f)

TWILIO_ACCOUNT_SID = twilio_cfg["account_sid"]
TWILIO_AUTH_TOKEN = twilio_cfg["auth_token"]
TWILIO_MESSAGING_SERVICE_SID = twilio_cfg["messaging_service_sid"]

with open(os.path.join(KEYS_DIR, "dkg-phone-encryption-key.json")) as f:
    FERNET_KEY = json.load(f)["key"]

fernet = Fernet(FERNET_KEY.encode())

BQ_PROJECT = "dkg-phd-thesis"
BQ_DATASET = "qualtrics"
BASE_SURVEY_URL = "https://ncsu.qualtrics.com/jfe/form"
SURVEY_IDS = [
    "SV_5nV942MJGubDmqq",
    "SV_eRKl4lgMZDAurT8",
    "SV_6J3svun1r97AAHc",
]
SMS_TEMPLATE = (
    "Hello, this is Demetrius K. Green. It is time for your "
    "{time} follow-up survey for the research study. Please "
    "complete it within 1 hour for your response to be valid: {url}"
)

# ---- Participants to cancel + reschedule --------------------------------

SECOND_SHIFT_PARTICIPANTS = [
    {
        "response_id": "R_7du3EETjpjYpC2B",
        "timezone": "US/Eastern",
        "selected_date": "2026-06-03",
        "phone_enc": (
            "gAAAAABqHaPyCVZGNgpMIcf4IH0mfm8F8nbg9SktA2-SznxMa2eI6ersaRW"
            "ic7WE301CokEi6y89s9hje1x6qYqzNnZv7uZEtA=="
        ),
        "old_sids": [
            "SM536dd6a7442cc0dea7fade980fa7f158",
            "SM25377bd8f11dff5b1e4b91b549d22e32",
            "SM69ad83f5913829b7fb9daaa90c55c829",
        ],
        "new_utc_times": [
            "2026-06-03T20:00:00+00:00",
            "2026-06-03T23:00:00+00:00",
            "2026-06-04T02:00:00+00:00",
        ],
    },
    {
        "response_id": "R_7o0H1ol9a1u5sC8",
        "timezone": "US/Central",
        "selected_date": "2026-06-04",
        "phone_enc": (
            "gAAAAABqHbbQKY-hH-mtZEObYRS94vH8MAeg89qvYo-fn3_zIYY2oXcOmiQr"
            "wNYoQ9rMZNyinnphD98UWTzzKRTc0JuabdcmxQ=="
        ),
        "old_sids": [
            "SMa5e42ebdaeacd84ddc8c2cdce72b56b5",
            "SM164b54fea887181415a5de1d651152a9",
            "SM7b4a041f9f049c9c4c1d0acbe0852140",
        ],
        "new_utc_times": [
            "2026-06-04T21:00:00+00:00",
            "2026-06-05T00:00:00+00:00",
            "2026-06-05T03:00:00+00:00",
        ],
    },
]

# Null-shift participants correctly scheduled at first_shift times.
# Only BQ update needed (no Twilio changes).
FIRST_SHIFT_NULL_PARTICIPANTS = [
    "R_7MM9VouuPzLOsfv",
    "R_6OqN8tERrSZT0Nr",
    "R_7OGO6hGgI7JUqB3",
]


def format_time_label(dt: datetime) -> str:
    hour = dt.hour
    period = "AM" if hour < 12 else "PM"
    display_hour = hour if hour <= 12 else hour - 12
    if display_hour == 0:
        display_hour = 12
    return f"{display_hour}:{dt.minute:02d} {period}"


def build_survey_url(
    survey_id: str, response_id: str, survey_time: int, selected_date: str
) -> str:
    return (
        f"{BASE_SURVEY_URL}/{survey_id}"
        f"?response_id={response_id}"
        f"&survey_time={survey_time}"
        f"&selected_date={selected_date}"
    )


def cancel_twilio_message(client: TwilioClient, sid: str) -> str:
    if DRY_RUN:
        print(f"  [DRY RUN] Would cancel {sid}")
        return "canceled"
    msg = client.messages(sid).update(status="canceled")
    return msg.status


def schedule_twilio_message(
    client: TwilioClient, phone: str, body: str, send_at: datetime
) -> str:
    if DRY_RUN:
        print(
            f"  [DRY RUN] Would schedule SMS to "
            f"{phone[:2]}***{phone[-4:]} at {send_at.isoformat()}"
        )
        return "DRY_RUN_SID"
    msg = client.messages.create(
        messaging_service_sid=TWILIO_MESSAGING_SERVICE_SID,
        to=phone,
        body=body,
        schedule_type="fixed",
        send_at=send_at,
    )
    return msg.sid


def run() -> None:
    bq = bigquery.Client(project=BQ_PROJECT)
    twilio = TwilioClient(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)

    print(f"\n{'=' * 60}")
    print(f"Shift Remediation -- {'DRY RUN' if DRY_RUN else 'LIVE'}")
    print(f"{'=' * 60}\n")

    # -- Step 1: Verify all 6 wrong messages are still schedulable -------
    print("Step 1: Verify existing messages are cancelable")
    all_sids = [sid for p in SECOND_SHIFT_PARTICIPANTS for sid in p["old_sids"]]
    abort = False
    for sid in all_sids:
        msg = twilio.messages(sid).fetch()
        print(f"  {sid} -> {msg.status}")
        if msg.status != "scheduled":
            print(f"  ERROR: {sid} is '{msg.status}', not cancelable")
            abort = True
    if abort:
        print("\nAborting: one or more messages not cancelable.")
        sys.exit(1)
    print("  All 6 messages are 'scheduled' -- safe to cancel\n")

    # -- Step 2: Cancel 6 wrong messages ---------------------------------
    print("Step 2: Cancel 6 wrong Twilio messages")
    for participant in SECOND_SHIFT_PARTICIPANTS:
        rid = participant["response_id"]
        for sid in participant["old_sids"]:
            result = cancel_twilio_message(twilio, sid)
            print(f"  {rid} {sid} -> {result}")
    print()

    # -- Step 3: Update BQ stg_intake_responses --------------------------
    print(
        "Step 3: Update stg_intake_responses (work_shift + work_classification)"
    )
    update_second = f"""
UPDATE `{BQ_PROJECT}.{BQ_DATASET}.stg_intake_responses`
SET work_shift = 'second_shift',
    work_classification = 'Employee - Full-Time (30 to 40+ hrs/week)'
WHERE response_id IN ('R_7du3EETjpjYpC2B', 'R_7o0H1ol9a1u5sC8')
"""
    first_ids_sql = ", ".join(f"'{r}'" for r in FIRST_SHIFT_NULL_PARTICIPANTS)
    update_first = f"""
UPDATE `{BQ_PROJECT}.{BQ_DATASET}.stg_intake_responses`
SET work_shift = 'first_shift',
    work_classification = 'Employee - Full-Time (30 to 40+ hrs/week)'
WHERE response_id IN ({first_ids_sql})
"""
    if DRY_RUN:
        print("  [DRY RUN] Would run second_shift UPDATE (2 rows)")
        print("  [DRY RUN] Would run first_shift UPDATE (3 rows)")
    else:
        job = bq.query(update_second)
        job.result()
        print(
            f"  second_shift UPDATE: {job.num_dml_affected_rows} rows affected"
        )
        job = bq.query(update_first)
        job.result()
        print(
            f"  first_shift UPDATE: {job.num_dml_affected_rows} rows affected"
        )
    print()

    # -- Step 4: Schedule 6 new Twilio messages --------------------------
    print("Step 4: Schedule 6 new Twilio messages (second_shift times)")
    new_sids: dict[str, list[str]] = {}
    for participant in SECOND_SHIFT_PARTICIPANTS:
        rid = participant["response_id"]
        phone = fernet.decrypt(participant["phone_enc"].encode()).decode()
        new_sids[rid] = []
        for i, (utc_str, survey_id) in enumerate(
            zip(participant["new_utc_times"], SURVEY_IDS)
        ):
            send_at = datetime.fromisoformat(utc_str)
            slot = i + 1
            url = build_survey_url(
                survey_id, rid, slot, participant["selected_date"]
            )
            local_dt = send_at.astimezone(
                zoneinfo.ZoneInfo(participant["timezone"])
            )
            time_label = format_time_label(local_dt)
            body = SMS_TEMPLATE.format(time=time_label, url=url)
            sid = schedule_twilio_message(twilio, phone, body, send_at)
            new_sids[rid].append(sid)
            print(
                f"  {rid} slot {slot}: {utc_str} "
                f"({time_label} local), SID={sid}"
            )
    print()

    # -- Step 5: Replace scheduled_followups rows ------------------------
    print("Step 5: Replace scheduled_followups rows in BQ")
    second_ids_sql = "', '".join(
        p["response_id"] for p in SECOND_SHIFT_PARTICIPANTS
    )
    delete_sql = f"""
DELETE FROM `{BQ_PROJECT}.{BQ_DATASET}.scheduled_followups`
WHERE response_id IN ('{second_ids_sql}')
"""
    if DRY_RUN:
        print("  [DRY RUN] Would DELETE 6 old rows")
    else:
        job = bq.query(delete_sql)
        job.result()
        print(f"  DELETE: {job.num_dml_affected_rows} rows removed")

    for participant in SECOND_SHIFT_PARTICIPANTS:
        rid = participant["response_id"]
        phone_enc = participant["phone_enc"]
        for i, (utc_str, survey_id, new_sid) in enumerate(
            zip(participant["new_utc_times"], SURVEY_IDS, new_sids[rid])
        ):
            slot = i + 1
            send_at_str = datetime.fromisoformat(utc_str).strftime(
                "%Y-%m-%d %H:%M:%S"
            )
            url = build_survey_url(
                survey_id, rid, slot, participant["selected_date"]
            )
            insert_sql = f"""
INSERT INTO `{BQ_PROJECT}.{BQ_DATASET}.scheduled_followups`
  (response_id, connect_id, phone, selected_date, timezone, survey_time,
   twilio_message_sid, send_at_utc, survey_url, _scheduled, _created_at)
VALUES
  ('{rid}', NULL, '{phone_enc}', '{participant["selected_date"]}',
   '{participant["timezone"]}', {slot}, '{new_sid}',
   '{send_at_str}', '{url}',
   TRUE, CURRENT_TIMESTAMP())
"""
            if DRY_RUN:
                print(f"  [DRY RUN] Would INSERT {rid} slot {slot}")
            else:
                job = bq.query(insert_sql)
                job.result()
                print(f"  INSERT {rid} slot {slot}: SID={new_sid}")
    print()

    # -- Step 6: Final verification --------------------------------------
    print("Step 6: Final verification")
    if not DRY_RUN:
        verify_intake = f"""
SELECT response_id, work_shift, work_classification
FROM `{BQ_PROJECT}.{BQ_DATASET}.stg_intake_responses`
WHERE response_id IN (
  'R_7du3EETjpjYpC2B', 'R_7o0H1ol9a1u5sC8',
  'R_7MM9VouuPzLOsfv', 'R_6OqN8tERrSZT0Nr', 'R_7OGO6hGgI7JUqB3'
)
ORDER BY response_id
"""
        print("  stg_intake_responses:")
        for row in bq.query(verify_intake).result():
            print(
                f"    {row.response_id}: "
                f"shift={row.work_shift}, "
                f"classification={row.work_classification}"
            )

        verify_followups = f"""
SELECT response_id, survey_time, send_at_utc, twilio_message_sid
FROM `{BQ_PROJECT}.{BQ_DATASET}.scheduled_followups`
WHERE response_id IN ('R_7du3EETjpjYpC2B', 'R_7o0H1ol9a1u5sC8')
ORDER BY response_id, survey_time
"""
        print("  scheduled_followups (second_shift participants):")
        for row in bq.query(verify_followups).result():
            print(
                f"    {row.response_id} slot {row.survey_time}: "
                f"{row.send_at_utc} SID={row.twilio_message_sid}"
            )
    else:
        print("  [DRY RUN] Skipping BQ verification")

    print(f"\n{'=' * 60}")
    print(f"Remediation {'(DRY RUN) ' if DRY_RUN else ''}complete.")
    print(f"{'=' * 60}\n")


if __name__ == "__main__":
    run()
