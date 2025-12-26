"""
Qualtrics API interaction utilities.
Handles response fetching from Qualtrics API.
"""

import logging
import os
from typing import Any, Dict, Optional

import requests
from box import Box

logger = logging.getLogger(__name__)


def fetch_single_response(
    survey_id: str, response_id: str, config: Box
) -> Optional[Dict[str, Any]]:
    """
    Fetches a single survey response from Qualtrics API.

    Uses GET /surveys/{surveyId}/responses/{responseId} endpoint.
    API Reference: https://api.qualtrics.com/1179a68b7183c-retrieve-a-survey-response

    Args:
        survey_id: Qualtrics survey identifier
        response_id: Specific response identifier from webhook
        config: Configuration Box with API credentials

    Returns:
        dict: Response data or None if request fails
    """
    try:
        QUALTRICS_KEY = os.environ["QUALTRICS_API_KEY"]
        base_url = config.params.qualtrics.base_url

        url = f"{base_url}/surveys/{survey_id}/responses/{response_id}"
        headers = {"X-API-TOKEN": QUALTRICS_KEY, "Content-Type": "application/json"}

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
    url = f"{base_url}/{survey_id}?ResponseID={response_id}&Timepoint={timepoint}"
    return url
