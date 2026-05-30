"""Cloud Function entry point for dashboard data export.

Queries BigQuery for current study metrics (enrollment count and
per-wave follow-up response rates) and deploys a fresh data.json to
the Netlify site via the Netlify Deploy API.

The site/ subdirectory is bundled with this function and contains
the static assets (index.html, netlify.toml). On each invocation,
a full Netlify deploy is created; only data.json changes each run --
the static files are served from Netlify's CDN cache by SHA1.

Trigger: HTTP (called by Cloud Scheduler, hourly).
"""

import hashlib
import json
import logging
import os
from datetime import UTC, datetime
from pathlib import Path

import functions_framework
import requests
from flask import Request, Response, jsonify
from google.cloud import bigquery
from shared.utils.config_loader import load_config

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

_config_path = Path(__file__).resolve().parent / "configs"
config = load_config(_config_path)

_SITE_DIR = Path(__file__).resolve().parent / "site"
_NETLIFY_API = "https://api.netlify.com/api/v1"

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
    """Export aggregate study metrics to the Netlify dashboard site.

    Args:
        request: Flask request object from Cloud Scheduler.

    Returns:
        Tuple of (JSON response, HTTP status code).
    """
    try:
        data = _build_export_data()
        _deploy_to_netlify(data)
        logger.info(
            "Dashboard export complete: %d enrolled, %d wave(s) deployed",
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


def _deploy_to_netlify(data: dict) -> None:
    """Deploy updated data.json to the Netlify site via the Deploy API.

    Builds a full deploy manifest from site/ static assets plus the
    freshly generated data.json. Netlify serves static files from its
    CDN by SHA1; only data.json is uploaded on each invocation.

    Args:
        data: Dashboard payload dict to serialize as data.json.

    Raises:
        requests.HTTPError: If any Netlify API call fails.
        KeyError: If NETLIFY_API_KEY env var is not set.
    """
    token = os.environ["NETLIFY_API_KEY"].strip()
    if config.netlify is None:
        raise RuntimeError("netlify config section missing from gcp_utils.yaml")
    site_id = config.netlify.site_id

    headers_auth = {"Authorization": f"Bearer {token}"}

    # Build file manifest: static assets + data.json
    file_contents: dict[str, bytes] = {}
    for static_file in _SITE_DIR.iterdir():
        if static_file.is_file():
            file_contents[f"/{static_file.name}"] = static_file.read_bytes()

    data_bytes = json.dumps(data, indent=2).encode()
    file_contents["/data.json"] = data_bytes

    manifest = {
        path: hashlib.sha1(content).hexdigest()
        for path, content in file_contents.items()
    }

    # Create deploy
    resp = requests.post(
        f"{_NETLIFY_API}/sites/{site_id}/deploys",
        headers={**headers_auth, "Content-Type": "application/json"},
        json={"files": manifest},
        timeout=30,
    )
    resp.raise_for_status()
    deploy = resp.json()
    deploy_id = deploy["id"]
    required = set(deploy.get("required", []))

    logger.info(
        "Netlify deploy %s created; %d file(s) to upload",
        deploy_id,
        len(required),
    )

    # Upload only the files Netlify doesn't already have cached
    for file_path in required:
        norm = file_path if file_path.startswith("/") else f"/{file_path}"
        content = file_contents.get(norm)
        if content is None:
            raise KeyError(
                f"Netlify requested file not in manifest: {file_path}"
            )
        upload = requests.put(
            f"{_NETLIFY_API}/deploys/{deploy_id}/files{norm}",
            headers={
                **headers_auth,
                "Content-Type": "application/octet-stream",
            },
            data=content,
            timeout=30,
        )
        upload.raise_for_status()
        logger.info("Uploaded %s to deploy %s", norm, deploy_id)

    logger.info("Netlify deploy %s complete for site %s", deploy_id, site_id)
