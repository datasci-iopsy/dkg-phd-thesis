"""Publish Pub/Sub messages for intake responses not yet scheduled.

Queries stg_intake_responses for rows with _processed=FALSE and
publishes an IntakeProcessedMessage for each one directly to the
dkg-intake-processed topic. run-intake-confirmation will pick each
message up, send the confirmation SMS, set _processed=TRUE, and
hand off to run-followup-scheduling.

Phone numbers are already Fernet-encrypted in BigQuery; this script
reads them as-is and puts them on the message. No re-encryption.

Usage:
    uv run gcp/deploy/trigger_unscheduled_participants.py [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import sys
import time

from google.cloud import bigquery, pubsub_v1

GCP_PROJECT = "dkg-phd-thesis"
BQ_TABLE = "dkg-phd-thesis.qualtrics.stg_intake_responses"
TOPIC_ID = "dkg-intake-processed"


def get_unscheduled() -> list[dict]:
    client = bigquery.Client(project=GCP_PROJECT)
    query = f"""
        SELECT
            response_id,
            connect_id,
            phone,
            selected_date,
            timezone
        FROM `{BQ_TABLE}`
        WHERE _processed = FALSE
        ORDER BY _created_at
    """
    rows = list(client.query(query).result())
    return [dict(r) for r in rows]


def publish_message(publisher: pubsub_v1.PublisherClient, message: dict) -> str:
    topic_path = publisher.topic_path(GCP_PROJECT, TOPIC_ID)
    data = json.dumps(message).encode("utf-8")
    future = publisher.publish(topic_path, data=data)
    return future.result()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print messages without publishing",
    )
    args = parser.parse_args()

    print("Querying BigQuery for unscheduled participants...")
    rows = get_unscheduled()
    print(f"  {len(rows)} rows with _processed=FALSE\n")

    if not rows:
        print("Nothing to do.")
        return

    missing_fields = []
    for r in rows:
        if not r.get("phone"):
            missing_fields.append(f"{r['response_id']}: missing phone")
        if not r.get("selected_date"):
            missing_fields.append(f"{r['response_id']}: missing selected_date")
        if not r.get("timezone"):
            missing_fields.append(f"{r['response_id']}: missing timezone")

    if missing_fields:
        print("ERROR: rows with missing required fields (cannot schedule):")
        for m in missing_fields:
            print(f"  {m}")
        sys.exit(1)

    if args.dry_run:
        for r in rows:
            print(
                f"DRY RUN {r['response_id']}: "
                f"date={r['selected_date']} tz={r['timezone']} "
                f"connect_id={r['connect_id']!r}"
            )
        print(f"\nDRY RUN: would publish {len(rows)} messages")
        return

    publisher = pubsub_v1.PublisherClient()
    success = 0
    failed = []

    for r in rows:
        msg = {
            "response_id": r["response_id"],
            "connect_id": r["connect_id"],
            "phone": r["phone"],
            "selected_date": r["selected_date"],
            "timezone": r["timezone"],
            "send_immediately": False,
        }
        try:
            message_id = publish_message(publisher, msg)
            print(
                f"  OK   {r['response_id']} -> message_id={message_id} "
                f"(date={r['selected_date']}, tz={r['timezone']})"
            )
            success += 1
        except Exception as e:
            print(f"  FAIL {r['response_id']} -> {e}")
            failed.append(r["response_id"])

        time.sleep(0.25)

    print(f"\nDone: {success} published, {len(failed)} failed")
    if failed:
        print("Failed IDs:", failed)
        sys.exit(1)


if __name__ == "__main__":
    main()
