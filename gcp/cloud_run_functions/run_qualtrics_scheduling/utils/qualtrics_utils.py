"""Qualtrics API interaction utilities.

Handles fetching survey responses from the Qualtrics REST API
and constructing follow-up survey URLs.
"""

import logging
import os

import requests
from models.qualtrics import QualtricsResponse
from shared.utils.config_models import AppConfig

logger = logging.getLogger(__name__)


def fetch_single_response(
    survey_id: str, response_id: str, config: AppConfig
) -> QualtricsResponse | None:
    """Fetch a single survey response from the Qualtrics API.

    Uses GET /surveys/{surveyId}/responses/{responseId}.
    API reference:
        https://api.qualtrics.com/1179a68b7183c-retrieve-a-survey-response

    Args:
        survey_id: Qualtrics survey identifier.
        response_id: Specific response identifier from webhook.
        config: Validated application configuration.

    Returns:
        Parsed QualtricsResponse, or None if the request fails.
    """
    try:
        api_key = os.environ["QUALTRICS_API_KEY"]
        base_url = config.qualtrics.base_url

        url = f"{base_url}/surveys/{survey_id}/responses/{response_id}"
        headers = {
            "X-API-TOKEN": api_key,
            "Content-Type": "application/json",
        }

        logger.info("Fetching response %s from Qualtrics API", response_id)
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()

        data = response.json()
        result = QualtricsResponse.model_validate(data)

        logger.info("Successfully fetched response %s", response_id)
        return result

    except requests.exceptions.HTTPError as e:
        logger.error(
            "HTTP error fetching response: %s - %s",
            e.response.status_code,
            e.response.text,
        )
        return None
    except requests.exceptions.RequestException as e:
        logger.error("Request error fetching response: %s", e, exc_info=True)
        return None
    except Exception as e:
        logger.error("Unexpected error fetching response: %s", e, exc_info=True)
        return None


def build_followup_survey_url(
    survey_id: str, response_id: str, timepoint: int, config: AppConfig
) -> str:
    """Construct a follow-up survey URL with embedded metadata.

    Args:
        survey_id: Qualtrics survey identifier.
        response_id: Original response ID for linking.
        timepoint: Survey timepoint (1, 2, or 3).
        config: Validated application configuration.

    Returns:
        Complete survey URL with query parameters.
    """
    base_url = config.qualtrics.survey_base_url
    return (
        f"{base_url}/{survey_id}?ResponseID={response_id}&Timepoint={timepoint}"
    )
