"""Cloud Function entry point for Qualtrics survey webhook.

Processes survey responses received from a Qualtrics Workflow
Web Service task. The payload contains the full response data
with semantic field names -- no follow-up API call needed.

Workflow:
    1. Parse and validate the incoming Web Service payload
    2. Write the survey response to BigQuery as explicit columns
    3. Extract and validate participant scheduling data
    4. Publish participant data to Pub/Sub for async confirmation
    5. Return a success response

The Pub/Sub publish in step 4 is non-blocking for the webhook
response. If publishing fails, the BQ write has already succeeded
(data is preserved) and _processed remains FALSE, giving
visibility into unconfirmed responses.
"""

import logging
import re
from pathlib import Path

import functions_framework
from flask import Request, jsonify
from shared.utils.bq_schemas import SURVEY_RESPONSES_SCHEMA
from shared.utils.config_loader import load_config
from shared.utils.crypto_utils import encrypt_phone
from shared.utils.gcp_utils import insert_survey_response
from shared.utils.phone_utils import normalize_phone_number
from shared.utils.pubsub_utils import (
    ConnectSchedulingMessage,
    IntakeProcessedMessage,
    publish_connect_scheduling,
    publish_intake_processed,
)
from utils import validation_utils

_CONNECT_ID_RE = re.compile(r"^[0-9A-Fa-f]{32}$")


def _is_connect_participant(connect_id: str | None) -> bool:
    """Return True if connect_id is a 32-hex CloudResearch Connect ID."""
    if not connect_id:
        return False
    return bool(_CONNECT_ID_RE.match(connect_id))


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
        # Step 1: Parse and validate the web service payload.
        # Also read send_immediately from the raw body -- it is not
        # part of WebServicePayload / BQ schema (test-only flag).
        raw_body = request.get_json(silent=True) or {}
        send_immediately = bool(raw_body.get("send_immediately", False))

        payload = validation_utils.extract_web_service_payload(request)
        if not payload:
            logger.error("Invalid or missing web service payload")
            return jsonify({"error": "Invalid payload"}), 400

        logger.info(
            "Processing response: %s (survey: %s, send_immediately: %s)",
            payload.response_id,
            payload.survey_id,
            send_immediately,
        )

        # Step 2: Write survey response to BigQuery (phone encrypted)
        _raw_phone = payload.phone
        _norm_phone = normalize_phone_number(_raw_phone) if _raw_phone else None
        bq_payload = payload.model_copy(
            update={
                "phone": encrypt_phone(_norm_phone) if _norm_phone else None
            }
        )
        write_success = insert_survey_response(
            payload=bq_payload,
            table_name=config.bq.tables.intake_raw,
            config=config,
            schema=SURVEY_RESPONSES_SCHEMA,
        )

        if not write_success:
            logger.error("BigQuery insert failed for %s", payload.response_id)
            return jsonify({"error": "Database write failed"}), 500

        # Step 3a: Route Connect participants to the Connect pipeline.
        # fn2 and fn3 are bypassed entirely -- Connect participants have
        # no usable phone and receive messages via the Connect platform.
        if _is_connect_participant(payload.connect_id):
            connect_participant = (
                validation_utils.extract_connect_participant_data(payload)
            )
            if not connect_participant:
                logger.error(
                    "Invalid Connect participant data for %s",
                    payload.response_id,
                )
                return (
                    jsonify(
                        {"error": "Invalid Connect participant information"}
                    ),
                    400,
                )
            connect_message = ConnectSchedulingMessage(
                response_id=connect_participant.response_id,
                connect_id=connect_participant.connect_id,
                selected_date=connect_participant.selected_date.isoformat(),
                timezone=connect_participant.timezone,
                send_immediately=send_immediately,
                work_shift=connect_participant.work_shift,
            )
            connect_message_id = publish_connect_scheduling(
                connect_message, config
            )
            if not connect_message_id:
                logger.warning(
                    "Connect Pub/Sub publish failed for %s -- "
                    "BQ write succeeded, _processed remains FALSE",
                    payload.response_id,
                )
            logger.info(
                "Routed Connect participant %s (connect_id: %s, published: %s)",
                payload.response_id,
                connect_participant.connect_id,
                bool(connect_message_id),
            )
            return (
                jsonify(
                    {
                        "status": "success",
                        "response_id": payload.response_id,
                        "path": "connect",
                        "published": bool(connect_message_id),
                    }
                ),
                200,
            )

        # Step 3: Extract and validate participant scheduling data
        participant = validation_utils.extract_participant_data(payload)

        if not participant:
            logger.error("Invalid participant data for %s", payload.response_id)
            return jsonify({"error": "Invalid participant information"}), 400

        # Step 4: Publish to Pub/Sub for async confirmation
        message = IntakeProcessedMessage(
            response_id=participant.response_id,
            connect_id=participant.connect_id,
            phone=participant.phone,
            selected_date=participant.selected_date.isoformat(),
            timezone=participant.timezone,
            send_immediately=send_immediately,
            work_shift=participant.work_shift,
        )

        message_id = publish_intake_processed(message, config)

        if not message_id:
            # Log but do not fail the webhook -- BQ write succeeded
            # and _processed=FALSE gives visibility into the gap.
            logger.warning(
                "Pub/Sub publish failed for %s -- BQ write succeeded, "
                "_processed remains FALSE",
                payload.response_id,
            )

        # Step 5: Return success
        logger.info(
            "Successfully processed response %s (phone: %s, published: %s)",
            payload.response_id,
            participant.phone_masked,
            bool(message_id),
        )
        return jsonify(
            {
                "status": "success",
                "response_id": payload.response_id,
                "participant_phone": participant.phone_masked,
                "published": bool(message_id),
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
