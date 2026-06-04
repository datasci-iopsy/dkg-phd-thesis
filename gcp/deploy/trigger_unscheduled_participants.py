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
    uv run gcp/deploy/trigger_unscheduled_participants.py --response-ids R_abc,R_def [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import date

from google.cloud import bigquery, pubsub_v1

GCP_PROJECT = "dkg-phd-thesis"
BQ_TABLE = "dkg-phd-thesis.qualtrics.stg_intake_responses"
TOPIC_ID = "dkg-intake-processed"


def get_unscheduled(
    response_ids: list[str] | None = None,
    skip_today: bool = True,
) -> list[dict]:
    client = bigquery.Client(project=GCP_PROJECT)

    if response_ids:
        query = """
            SELECT
                response_id,
                connect_id,
                phone,
                selected_date,
                timezone,
                work_shift
            FROM `dkg-phd-thesis.qualtrics.stg_intake_responses`
            WHERE _processed = FALSE
              AND response_id IN UNNEST(@ids)
            ORDER BY _created_at
        """
        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ArrayQueryParameter("ids", "STRING", response_ids),
            ]
        )
        rows = list(client.query(query, job_config=job_config).result())
    else:
        today_filter = (
            f"AND selected_date != '{date.today().isoformat()}'"
            if skip_today
            else ""
        )
        query = f"""
            SELECT
                response_id,
                connect_id,
                phone,
                selected_date,
                timezone,
                work_shift
            FROM `{BQ_TABLE}`
            WHERE _processed = FALSE
            {today_filter}
            ORDER BY _created_at
        """
        rows = list(client.query(query).result())

    return [dict(r) for r in rows]


def build_message(row: dict) -> dict:
    selected_date = row["selected_date"]
    if hasattr(selected_date, "isoformat"):
        selected_date = selected_date.isoformat()
    return {
        "response_id": row["response_id"],
        "connect_id": row["connect_id"],
        "phone": row["phone"],
        "selected_date": selected_date,
        "timezone": row["timezone"],
        "work_shift": row.get("work_shift"),
        "send_immediately": False,
    }


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
    parser.add_argument(
        "--response-ids",
        help="Comma-separated response_ids to target (bypasses skip_today filter)",
    )
    args = parser.parse_args()

    response_ids: list[str] | None = None
    if args.response_ids:
        response_ids = [
            r.strip() for r in args.response_ids.split(",") if r.strip()
        ]

    if response_ids:
        print(
            f"Querying BigQuery for {len(response_ids)} specified response_id(s)..."
        )
        rows = get_unscheduled(response_ids=response_ids)
    else:
        today = date.today().isoformat()
        print(
            f"Querying BigQuery for unscheduled participants (skipping {today})..."
        )
        rows = get_unscheduled(skip_today=True)
        print(
            f"  {len(rows)} rows with _processed=FALSE and selected_date > today\n"
        )

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
            msg = build_message(r)
            print(
                f"DRY RUN {r['response_id']}: "
                f"date={msg['selected_date']} tz={msg['timezone']} "
                f"work_shift={msg['work_shift']!r} "
                f"connect_id={msg['connect_id']!r}"
            )
        print(f"\nDRY RUN: would publish {len(rows)} messages")
        return

    publisher = pubsub_v1.PublisherClient()
    success = 0
    failed = []

    for r in rows:
        msg = build_message(r)
        try:
            message_id = publish_message(publisher, msg)
            print(
                f"  OK   {r['response_id']} -> message_id={message_id} "
                f"(date={msg['selected_date']}, tz={msg['timezone']}, "
                f"work_shift={msg['work_shift']!r})"
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
