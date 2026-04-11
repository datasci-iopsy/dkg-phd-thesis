"""Cloud Function entry point for followup survey response ingestion.

Receives completed followup survey responses from Qualtrics Workflow
Web Service tasks. All three daily surveys (9AM/1PM/5PM) POST to this
endpoint -- the `timepoint` field in the payload distinguishes them.

This is a terminal function: no downstream Pub/Sub publishing.

Workflow:
    1. Parse and validate the incoming Web Service payload
    2. Write the survey response to BigQuery
    3. Return a success response
"""

import logging
from pathlib import Path

import functions_framework
from flask import Request, Response, jsonify
from models.followup import FollowupWebServicePayload
from shared.utils.bq_schemas import FOLLOWUP_RESPONSES_SCHEMA
from shared.utils.config_loader import load_config
from shared.utils.gcp_utils import insert_survey_response

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


@functions_framework.http
def followup_response_handler(request: Request) -> tuple[Response, int]:
    """Webhook endpoint for Qualtrics followup survey completions.

    Receives the full followup survey response from a Qualtrics
    Workflow Web Service task. All three daily surveys (9AM/1PM/5PM)
    post to this endpoint; the timepoint field differentiates them.

    Args:
        request: Flask request object from the Qualtrics Web Service
            task, routed via the API Gateway /followup path.

    Returns:
        Tuple of (JSON response, HTTP status code).
    """
    try:
        raw_body = request.get_json(silent=True) or {}

        payload = _extract_followup_payload(raw_body)

        logger.info(
            "Processing followup response: %s (survey: %s, timepoint: %s)",
            payload.response_id,
            payload.survey_id,
            payload.timepoint,
        )

        write_success = insert_survey_response(
            payload=payload,
            table_name=config.bq.tables.followup_raw,
            config=config,
            schema=FOLLOWUP_RESPONSES_SCHEMA,
        )

        if not write_success:
            logger.error("BigQuery insert failed for %s", payload.response_id)
            return jsonify({"error": "Database write failed"}), 500

        logger.info(
            "Successfully stored followup response %s "
            "(timepoint: %s, connect_id: %s)",
            payload.response_id,
            payload.timepoint,
            payload.connect_id,
        )
        return jsonify(
            {
                "status": "success",
                "response_id": payload.response_id,
                "timepoint": payload.timepoint,
            }
        ), 200

    except ValueError as e:
        logger.error("Validation error: %s", e, exc_info=True)
        return jsonify({"error": str(e)}), 400
    except Exception as e:
        logger.error(
            "Unexpected error in followup handler: %s", e, exc_info=True
        )
        return jsonify({"error": "Internal server error"}), 500


def _extract_followup_payload(
    raw_body: dict,
) -> FollowupWebServicePayload:
    """Parse and validate a raw request body as a followup payload.

    Args:
        raw_body: Parsed JSON dict from the request body.

    Returns:
        Validated FollowupWebServicePayload.

    Raises:
        pydantic.ValidationError: If the payload fails validation.
    """
    return FollowupWebServicePayload.model_validate(raw_body)
