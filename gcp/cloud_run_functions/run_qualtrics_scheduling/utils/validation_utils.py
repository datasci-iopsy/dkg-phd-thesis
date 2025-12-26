"""
Data validation and extraction utilities.
"""

import hashlib
import hmac
import logging
from datetime import date, datetime
from typing import Any, Dict, Optional

from flask import Request
from models.participant import ParticipantData

logger = logging.getLogger(__name__)


def verify_webhook_signature(request: Request, webhook_secret: str) -> bool:
    """
    Verifies HMAC-SHA256 signature from Qualtrics webhook.

    Args:
        request: Flask request object containing webhook data
        webhook_secret: Shared secret configured in Qualtrics

    Returns:
        bool: True if signature is valid
    """
    if not webhook_secret:
        logger.warning("Webhook secret not configured, skipping verification")
        return True

    signature_header = request.headers.get("X-Qualtrics-Signature")
    if not signature_header:
        logger.error("Missing X-Qualtrics-Signature header")
        return False

    payload = request.get_data()
    expected_signature = hmac.new(
        webhook_secret.encode("utf-8"), payload, hashlib.sha256
    ).hexdigest()

    is_valid = hmac.compare_digest(signature_header, expected_signature)

    if is_valid:
        logger.info("Webhook signature verified successfully")
    else:
        logger.error("Webhook signature mismatch")

    return is_valid


def extract_webhook_payload(request: Request) -> Optional[Dict[str, Any]]:
    """
    Extracts and validates webhook payload from Qualtrics.

    Handles the POST payload sent by Qualtrics event subscriptions when
    a survey response is completed.

    Args:
        request: Flask request object

    Returns:
        dict: Validated webhook data with survey_id, response_id, and metadata
    """
    try:
        webhook_data = request.get_json(silent=True, force=True)

        if not webhook_data:
            logger.error("No JSON payload in request")
            return None

        # Log for debugging
        logger.info(f"Received webhook payload: {webhook_data}")

        # Extract required fields (Qualtrics uses these exact field names)
        response_id = webhook_data.get("ResponseID")
        survey_id = webhook_data.get("SurveyID")
        status = webhook_data.get("Status")
        topic = webhook_data.get("Topic", "")

        # Validate required fields
        if not all([response_id, survey_id]):
            logger.error(f"Missing required webhook fields: {webhook_data}")
            return None

        # Validate this is a completion event
        if "completedResponse" not in topic:
            logger.warning(f"Ignoring non-completion event: {topic}")
            return None

        # Only process completed responses
        if status and status.lower() != "complete":
            logger.info(
                f"Ignoring non-complete response: {response_id} (status: {status})"
            )
            return None

        return {
            "response_id": response_id,
            "survey_id": survey_id,
            "status": status,
            "topic": topic,
            "brand_id": webhook_data.get("BrandID"),
            "completed_date": webhook_data.get("CompletedDate"),
        }

    except Exception as e:
        logger.error(f"Error extracting webhook payload: {str(e)}", exc_info=True)
        return None


def extract_participant_data(
    response_data: Dict[str, Any], response_id: str
) -> Optional[ParticipantData]:
    """
    Extracts participant PII and preferences from Qualtrics response.

    IMPORTANT: Update the question IDs (QID1, QID2, etc.) to match
    your actual Qualtrics survey structure.

    Args:
        response_data: Complete response data from Qualtrics
        response_id: Response identifier

    Returns:
        ParticipantData: Validated participant data or None
    """
    try:
        values = response_data.get("values", {})

        # Extract fields - REPLACE THESE QIDs WITH YOUR ACTUAL QUESTION IDs
        raw_name = values.get("QID1_TEXT", "")
        raw_email = values.get("QID2_TEXT", "")
        raw_phone = values.get("QID3_TEXT", "")
        raw_date = values.get("QID4_TEXT", "")  # ISO date string
        consent_value = values.get("QID5", "")  # Checkbox: '1' = checked

        # Validate consent
        if consent_value != "1":
            logger.error(f"Consent not given for response {response_id}")
            return None

        # Parse and format phone number
        phone = format_phone_number(raw_phone)
        if not phone:
            logger.error(f"Invalid phone number for response {response_id}")
            return None

        # Parse selected date
        try:
            selected_date = datetime.fromisoformat(raw_date).date()
        except (ValueError, AttributeError):
            logger.error(f"Invalid date format: {raw_date}")
            return None

        # Create participant object
        participant = ParticipantData(
            response_id=response_id,
            name=raw_name.strip(),
            email=raw_email.strip().lower(),
            phone=phone,
            selected_date=selected_date,
            consent_given=True,
        )

        # Validate complete object
        if not participant.is_valid():
            logger.error(f"Participant validation failed for {response_id}")
            return None

        logger.info(f"Successfully extracted participant data for {response_id}")
        return participant

    except Exception as e:
        logger.error(f"Error extracting participant data: {str(e)}", exc_info=True)
        return None


def format_phone_number(raw_phone: str) -> Optional[str]:
    """
    Formats phone number to E.164 standard (+1234567890).

    Args:
        raw_phone: Raw phone number from survey

    Returns:
        str: E.164 formatted phone or None if invalid
    """
    try:
        # Remove all non-digit characters
        digits = "".join(filter(str.isdigit, raw_phone))

        # Handle US numbers (can be extended for international)
        if len(digits) == 10:
            return f"+1{digits}"
        elif len(digits) == 11 and digits[0] == "1":
            return f"+{digits}"
        elif raw_phone.startswith("+"):
            return raw_phone
        else:
            logger.warning(f"Unrecognized phone format: {raw_phone}")
            return None

    except Exception as e:
        logger.error(f"Error formatting phone number: {str(e)}")
        return None
