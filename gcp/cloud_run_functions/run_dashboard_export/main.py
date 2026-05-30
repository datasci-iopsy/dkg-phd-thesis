"""Cloud Function entry point for dashboard data export.

Queries BigQuery for current study metrics (enrollment count and
per-wave follow-up response rates) and writes a JSON snapshot to
Cloud Storage for the public Netlify dashboard to consume.

Trigger: HTTP (called by Cloud Scheduler, hourly).
"""

import json
import logging
from datetime import UTC, datetime
from pathlib import Path

import functions_framework
from flask import Request, Response, jsonify
from google.cloud import bigquery, storage
from shared.utils.config_loader import load_config

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

_config_path = Path(__file__).resolve().parent / "configs"
config = load_config(_config_path)

_WAVE_LABELS: dict[int, str] = {
    1: "Morning (9 AM)",
    2: "Afternoon (1 PM)",
    3: "Evening (5 PM)",
}

_EXPORT_QUERY = """
WITH intake AS (
    SELECT COUNT(*) AS total
    FROM `{project}.{dataset}.stg_intake_responses`
),
scheduled AS (
    SELECT
        survey_time AS wave,
        COUNT(*) AS scheduled_count
    FROM `{project}.{dataset}.scheduled_followups`
    GROUP BY survey_time
),
completed AS (
    SELECT
        timepoint AS wave,
        COUNT(*) AS completed_count
    FROM `{project}.{dataset}.stg_followup_responses`
    GROUP BY timepoint
)
SELECT
    s.wave,
    s.scheduled_count,
    COALESCE(c.completed_count, 0) AS completed_count,
    (SELECT total FROM intake) AS enrollment_total
FROM scheduled s
LEFT JOIN completed c ON s.wave = c.wave
ORDER BY s.wave
"""


@functions_framework.http
def dashboard_export_handler(request: Request) -> tuple[Response, int]:
    """Export aggregate study metrics to Cloud Storage.

    Args:
        request: Flask request object from Cloud Scheduler.

    Returns:
        Tuple of (JSON response, HTTP status code).
    """
    try:
        data = _build_export_data()
        _write_to_gcs(data)
        logger.info(
            "Dashboard export complete: %d enrolled, %d wave(s) exported",
            data["enrollment"]["total"],
            len(data["response_rates"]),
        )
        return jsonify({"status": "ok", "updated_at": data["updated_at"]}), 200
    except Exception as e:
        logger.error("Dashboard export failed: %s", e, exc_info=True)
        return jsonify({"error": "Export failed"}), 500


def _build_export_data() -> dict:
    """Query BigQuery and assemble the dashboard JSON payload.

    Returns:
        Dict with enrollment count, per-wave response rates, and
        overall follow-up response rate.
    """
    bq = bigquery.Client(project=config.gcp.project_id)
    query = _EXPORT_QUERY.format(
        project=config.gcp.project_id,
        dataset=config.bq.dataset_id,
    )
    rows = list(bq.query(query).result())

    enrollment_total = int(rows[0]["enrollment_total"]) if rows else 0
    response_rates = []
    total_scheduled = 0
    total_completed = 0

    for row in rows:
        wave = int(row["wave"])
        scheduled = int(row["scheduled_count"])
        completed = int(row["completed_count"])
        rate = round(completed / scheduled, 4) if scheduled > 0 else 0.0
        total_scheduled += scheduled
        total_completed += completed
        response_rates.append(
            {
                "wave": wave,
                "label": _WAVE_LABELS.get(wave, f"Wave {wave}"),
                "scheduled": scheduled,
                "completed": completed,
                "rate": rate,
            }
        )

    overall_rate = (
        round(total_completed / total_scheduled, 4)
        if total_scheduled > 0
        else 0.0
    )

    return {
        "updated_at": datetime.now(UTC).isoformat(),
        "enrollment": {"total": enrollment_total},
        "response_rates": response_rates,
        "overall_followup": {
            "scheduled": total_scheduled,
            "completed": total_completed,
            "rate": overall_rate,
        },
    }


def _write_to_gcs(data: dict) -> None:
    """Write the export payload as JSON to Cloud Storage.

    Args:
        data: Dashboard payload dict to serialize and upload.
    """
    assert config.storage is not None
    gcs = storage.Client(project=config.gcp.project_id)
    bucket = gcs.bucket(config.storage.bucket)
    blob = bucket.blob(config.storage.object_name)
    blob.cache_control = "no-cache, max-age=0"
    blob.upload_from_string(
        json.dumps(data, indent=2),
        content_type="application/json",
    )
    logger.info(
        "Wrote dashboard data to gs://%s/%s",
        config.storage.bucket,
        config.storage.object_name,
    )
