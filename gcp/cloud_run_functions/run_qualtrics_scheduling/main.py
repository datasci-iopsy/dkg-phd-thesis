"""Cloud Function entry point for Qualtrics survey webhook.

Processes survey responses received from a Qualtrics Workflow
Web Service task. The payload contains the full response data
with semantic field names -- no follow-up API call needed.

Workflow:
    1. Parse and validate the incoming Web Service payload
    2. Write the survey response to BigQuery as explicit columns
    3. Extract and validate participant scheduling data
    4. Return a success response
"""

import logging
from pathlib import Path

import functions_framework
from flask import Request, jsonify
from shared.utils.config_loader import load_config
from shared.utils.gcp_utils import insert_survey_response
from utils import validation_utils

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
def qualtrics_webhook_handler(request: Request):
    """Main webhook endpoint for Qualtrics survey completions.

    Receives the full survey response from a Qualtrics Workflow
    Web Service task. Unlike the event subscription pattern, this
    payload contains all response data -- no follow-up API call
    to Qualtrics is needed.

    Args:
        request: Flask request object from Qualtrics Web Service task.

    Returns:
        Tuple of (JSON response, HTTP status code).
    """
    try:
        # Step 1: Parse and validate the web service payload
        payload = validation_utils.extract_web_service_payload(request)
        if not payload:
            logger.error("Invalid or missing web service payload")
            return jsonify({"error": "Invalid payload"}), 400

        logger.info(
            "Processing response: %s (survey: %s)",
            payload.response_id,
            payload.survey_id,
        )

        # Step 2: Write survey response to BigQuery
        write_success = insert_survey_response(
            payload=payload,
            table_name=config.bq.tables.intake_raw,
            config=config,
        )

        if not write_success:
            logger.error("BigQuery insert failed for %s", payload.response_id)
            return jsonify({"error": "Database write failed"}), 500

        # Step 3: Extract and validate participant scheduling data
        participant = validation_utils.extract_participant_data(payload)

        if not participant:
            logger.error("Invalid participant data for %s", payload.response_id)
            return jsonify({"error": "Invalid participant information"}), 400

        # Step 4: Return success
        logger.info(
            "Successfully processed response %s (phone: %s)",
            payload.response_id,
            participant.phone_masked,
        )
        return jsonify(
            {
                "status": "success",
                "response_id": payload.response_id,
                "participant_phone": participant.phone_masked,
            }
        ), 200

    except ValueError as e:
        logger.error("Validation error: %s", e, exc_info=True)
        return jsonify({"error": str(e)}), 400
    except Exception as e:
        logger.error(
            "Unexpected error in webhook handler: %s", e, exc_info=True
        )
        return jsonify({"error": "Internal server error"}), 500
