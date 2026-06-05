"""Backfill intake survey responses that failed to reach the pipeline.

Reads a Qualtrics response export CSV, compares against BigQuery to find
responses not yet in stg_intake_responses, and POSTs each missing one to
the live intake endpoint exactly as the Qualtrics web service task would.

Usage:
    uv run gcp/deploy/backfill_intake_responses.py <csv_path> [--dry-run]
"""

from __future__ import annotations

import argparse
import csv
import os
import sys
import time
from pathlib import Path

import requests
from google.cloud import bigquery

GATEWAY_URL = "https://dkg-qualtrics-gateway-3zpc0p6y.uk.gateway.dev/"
API_KEY_NAME = "projects/312811716490/locations/global/keys/c834a3a1-3575-4ed5-a410-c24626065409"
_GCP_PROJECT = os.environ.get("GCP_PROJECT", "dkg-phd-thesis")
BQ_TABLE = f"{_GCP_PROJECT}.qualtrics.stg_intake_responses"

# CSV column name -> payload key sent to the intake endpoint.
# Keys match what the Qualtrics web service task sends (UPPERCASE field names
# that the AliasGenerator on WebServicePayload accepts).
COLUMN_MAP: dict[str, str] = {
    "ResponseID": "RESPONSE_ID",
    "SurveyID": "SURVEY_ID",
    "Q_TotalDuration": "DURATION",
    "IC2_FLAG": "CONSENT",
    "CONNECT_ID": "CONNECT_ID",
    "AGE_FLAG": "AGE_FLAG",
    "FTE_FLAG": "FTE_FLAG",
    "LOCATION_FLAG": "LOCATION_FLAG",
    "LANGUAGE_FLAG": "LANGUAGE_FLAG",
    "WORK_HOURS_FLAG": "WORK_HOURS_FLAG",
    "PHONE": "PHONE",
    "LOCAL_TZ": "TIMEZONE",
    "DATE": "SELECTED_DATE",
    "AGE": "AGE",
    "ETHNICITY": "ETHNICITY",
    "GENDER": "GENDER_IDENTITY",
    "JOB_TENURE": "JOB_TENURE",
    "EDU_LEVEL": "EDUCATION_LEVEL",
    "REMOTE_FLAG": "REMOTE_FLAG",
    "WORK_CLASSIFICATION": "WORK_CLASSIFICATION",
    "WORK_SHIFT": "WORK_SHIFT",
    "PA1": "PA1",
    "PA2": "PA2",
    "PA3": "PA3",
    "PA4": "PA4",
    "PA5": "PA5",
    "NA1": "NA1",
    "NA2": "NA2",
    "NA3": "NA3",
    "NA4": "NA4",
    "NA5": "NA5",
    "BR1": "BR1",
    "BR2": "BR2",
    "BR3": "BR3",
    "BR4": "BR4",
    "BR5": "BR5",
    "VIO1": "VIO1",
    "VIO2": "VIO2",
    "VIO3": "VIO3",
    "VIO4": "VIO4",
    "JS1": "JS1",
    "DES1": "DES1",
    "DES2": "DES2",
    "JIS1": "JIS1",
    "TURNOVER_INTENTION": "TURNOVER_INTENTION",
}


def get_api_key() -> str:
    import subprocess

    result = subprocess.run(
        [
            "gcloud",
            "services",
            "api-keys",
            "get-key-string",
            API_KEY_NAME,
            "--format=value(keyString)",
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def get_existing_response_ids() -> set[str]:
    client = bigquery.Client(project=_GCP_PROJECT)
    query = f"SELECT DISTINCT response_id FROM `{BQ_TABLE}`"
    return {row.response_id for row in client.query(query).result()}


def read_csv_responses(csv_path: Path) -> list[dict[str, str]]:
    """Read Qualtrics export CSV, skipping the 3 header rows."""
    with csv_path.open(newline="", encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        rows = list(reader)

    if len(rows) < 4:
        return []

    headers = rows[0]
    # rows[1] = question text, rows[2] = import IDs; data starts at rows[3]
    data_rows = rows[3:]

    responses = []
    for row in data_rows:
        # Keep the first occurrence of any duplicate column name.
        # The Qualtrics export repeats CONNECT_ID and Finished; the first
        # occurrence is the real survey response value; later ones are
        # embedded-data echoes that may be empty.
        record: dict[str, str] = {}
        for col, val in zip(headers, row):
            if col not in record:
                record[col] = val
        # Only complete responses with a real ResponseId
        response_id = record.get("ResponseId", "")
        if not response_id.startswith("R_"):
            continue
        if record.get("Finished", "").lower() not in ("true", "1"):
            continue
        responses.append(record)
    return responses


def build_payload(record: dict[str, str]) -> dict[str, str]:
    payload: dict[str, str] = {}
    for csv_col, payload_key in COLUMN_MAP.items():
        value = record.get(csv_col, "")
        if value:
            payload[payload_key] = value
    return payload


def post_response(payload: dict, api_key: str) -> tuple[int, dict]:
    resp = requests.post(
        GATEWAY_URL,
        json=payload,
        headers={
            "Content-Type": "application/json",
            "x-api-key": api_key,
        },
        timeout=30,
    )
    try:
        body = resp.json()
    except Exception:
        body = {"raw": resp.text}
    return resp.status_code, body


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "csv_path", type=Path, help="Qualtrics response export CSV"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print payloads without sending",
    )
    parser.add_argument(
        "--all-responses",
        action="store_true",
        help="Process all CSV rows, skipping the BigQuery dedup check",
    )
    args = parser.parse_args()

    if not args.csv_path.exists():
        print(f"ERROR: file not found: {args.csv_path}", file=sys.stderr)
        sys.exit(1)

    print("Reading CSV...")
    responses = read_csv_responses(args.csv_path)
    print(f"  {len(responses)} completed responses in CSV")

    if args.all_responses:
        missing = responses
        print(f"  --all-responses: processing all {len(missing)} rows\n")
    else:
        print("Querying BigQuery for existing response IDs...")
        existing = get_existing_response_ids()
        print(f"  {len(existing)} already in {BQ_TABLE}")
        missing = [r for r in responses if r["ResponseId"] not in existing]
        print(f"  {len(missing)} need backfill\n")

    if not missing:
        print("Nothing to do.")
        return

    if args.dry_run:
        for record in missing:
            payload = build_payload(record)
            print(f"DRY RUN {record['ResponseId']}: {list(payload.keys())}")
        return

    print("Fetching API key...")
    api_key = get_api_key()

    success = 0
    failed = []
    for record in missing:
        response_id = record["ResponseId"]
        payload = build_payload(record)

        if "RESPONSE_ID" not in payload or "SURVEY_ID" not in payload:
            print(
                f"  SKIP {response_id}: missing RESPONSE_ID or SURVEY_ID in CSV"
            )
            failed.append(response_id)
            continue

        status, body = post_response(payload, api_key)
        if status == 200:
            print(f"  OK   {response_id} -> {body}")
            success += 1
        else:
            print(f"  FAIL {response_id} -> HTTP {status}: {body}")
            failed.append(response_id)

        time.sleep(0.5)

    print(f"\nDone: {success} succeeded, {len(failed)} failed")
    if failed:
        print("Failed IDs:", failed)
        sys.exit(1)


if __name__ == "__main__":
    main()
