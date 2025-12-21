"""
Qualtrics API interaction utilities.
Handles authentication, webhook verification, and response fetching.
"""

import hmac
import hashlib
import logging
import requests
from typing import Optional, Dict, Any
from flask import Request
from box import Box

logger = logging.getLogger(__name__)


def verify_webhook_signature(request: Request, config: Box) -> bool:
    """
    Verifies HMAC-SHA256 signature from Qualtrics webhook.

    Args:
        request: Flask request object containing webhook data
        config: Configuration Box with webhook secret

    Returns:
        bool: True if signature is valid or verification is disabled
    """
    webhook_secret = config.params.qualtrics.get("webhook_secret")

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


def fetch_single_response(
    survey_id: str, response_id: str, config: Box
) -> Optional[Dict[str, Any]]:
    """
    Fetches a single survey response from Qualtrics API.

    This uses the GET /surveys/{surveyId}/responses/{responseId} endpoint
    which returns ONLY the specified response, not the full dataset.

    API Reference: https://api.qualtrics.com/6b00592b9c013-get-survey-response

    Args:
        survey_id: Qualtrics survey identifier
        response_id: Specific response identifier from webhook
        config: Configuration Box with API credentials

    Returns:
        dict: Response data or None if request fails
    """
    try:
        api_token = config.params.qualtrics.api_token
        data_center = config.params.qualtrics.data_center

        url = (
            f"https://{data_center}.qualtrics.com/API/v3/"
            f"surveys/{survey_id}/responses/{response_id}"
        )

        headers = {"X-API-TOKEN": api_token, "Content-Type": "application/json"}

        logger.info(f"Fetching response {response_id} from Qualtrics API")
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()

        data = response.json()
        result = data.get("result", {})

        logger.info(f"Successfully fetched response {response_id}")
        return result

    except requests.exceptions.HTTPError as e:
        logger.error(
            f"HTTP error fetching response: {e.response.status_code} - {e.response.text}"
        )
        return None

    except requests.exceptions.RequestException as e:
        logger.error(f"Request error fetching response: {str(e)}", exc_info=True)
        return None

    except Exception as e:
        logger.error(f"Unexpected error fetching response: {str(e)}", exc_info=True)
        return None


def build_followup_survey_url(
    survey_id: str, response_id: str, timepoint: int, config: Box
) -> str:
    """
    Constructs a follow-up survey URL with embedded metadata.

    Args:
        survey_id: Qualtrics survey identifier
        response_id: Original response ID for linking
        timepoint: Survey timepoint (1, 2, or 3)
        config: Configuration Box

    Returns:
        str: Complete survey URL with query parameters
    """
    base_url = config.params.qualtrics.survey_base_url

    # Embed metadata for response tracking
    url = f"{base_url}/{survey_id}?ResponseID={response_id}&Timepoint={timepoint}"

    return url
