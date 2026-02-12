"""
Cloud Function entry point for Qualtrics survey webhook.
Orchestrates the survey response processing workflow.
"""

import json
import logging
import os
from pathlib import Path

import functions_framework
from flask import Request, jsonify
from utils import qualtrics_utils, validation_utils

from shared.utils import common_utils, gcp_utils

# Configure logging
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

# Load configurations
py_file = Path(__file__).resolve()
config_path = py_file.parent / "configs"
config = common_utils.load_configs(config_path=str(config_path), use_box=True)
# logger.info(f"Loaded config with keys: {list(config.params.keys())}")
logger.info(f"Loaded config with keys: {json.dumps(config.params, indent=2)}")


@functions_framework.http
def qualtrics_webhook_handler(request: Request):
    """
    Main webhook endpoint for Qualtrics survey completions.

    Workflow:
        1. Validate webhook signature
        2. Extract webhook payload
        3. Fetch full response from Qualtrics API
        4. Write raw data to BigQuery
        5. Extract and validate participant data
        6. Return success response

    Args:
        request (Request): Flask request object from Qualtrics webhook

    Returns:
        tuple: JSON response and HTTP status code
    """
    try:
        # Step 1: Verify webhook signature for security
        # webhook_secret = os.environ.get("QUALTRICS_WEBHOOK_SECRET")
        # if not webhook_secret:
        #     logger.error("QUALTRICS_WEBHOOK_SECRET environment variable not set")
        #     return jsonify({"error": "Server configuration error"}), 500

        # if not validation_utils.verify_webhook_signature(request, webhook_secret):
        #     logger.warning("Invalid webhook signature received")
        #     return jsonify({"error": "Unauthorized"}), 401

        # Step 2: Extract and validate webhook payload
        webhook_data = validation_utils.extract_webhook_payload(request)
        if not webhook_data:
            logger.error("Invalid or missing webhook payload")
            return jsonify({"error": "Invalid payload"}), 400

        logger.info(f"Processing webhook for response: {webhook_data['response_id']}")

        # Step 3: Fetch complete survey response from Qualtrics
        response_data = qualtrics_utils.fetch_single_response(
            survey_id=webhook_data["survey_id"],
            response_id=webhook_data["response_id"],
            config=config,
        )

        if not response_data:
            logger.error(f"Failed to fetch response {webhook_data['response_id']}")
            return jsonify({"error": "Could not retrieve survey response"}), 500

        # # Step 4: Write raw response to BigQuery for audit trail
        # write_success = gcp_utils.insert_raw_response(
        #     response_data=response_data,
        #     survey_id=webhook_data["survey_id"],
        #     response_id=webhook_data["response_id"],
        #     config=config,
        # )

        # if not write_success:
        #     logger.error("BigQuery insert failed")
        #     return jsonify({"error": "Database write failed"}), 500

        # # Step 5: Extract and validate participant PII and preferences
        # participant = validation_utils.extract_participant_data(
        #     response_data=response_data, response_id=webhook_data["response_id"]
        # )

        # if not participant or not participant.is_valid():
        #     logger.error("Invalid participant data extracted")
        #     return jsonify({"error": "Invalid participant information"}), 400

        # # Return success response
        # return jsonify(
        #     {
        #         "status": "success",
        #         "response_id": webhook_data["response_id"],
        #         "participant_phone": participant.phone_masked,
        #     }
        # ), 200

    except ValueError as e:
        logger.error(f"Validation error: {str(e)}", exc_info=True)
        return jsonify({"error": str(e)}), 400
    except Exception as e:
        logger.error(f"Unexpected error in webhook handler: {str(e)}", exc_info=True)
        return jsonify({"error": "Internal server error"}), 500
