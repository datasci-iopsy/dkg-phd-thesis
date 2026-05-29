"""Qualtrics Survey Definitions API client.

Read-only. Fetches survey definitions; never mutates survey state.
"""

import logging

import requests
from pydantic import BaseModel

logger = logging.getLogger(__name__)

TIMEOUT_SECONDS = 30


class Question(BaseModel):
    question_id: str
    question_text: str
    question_type: str
    question_name: str | None = None


class SurveyDefinition(BaseModel):
    survey_id: str
    survey_name: str
    questions: list[Question]


def fetch_survey_definition(
    survey_id: str,
    base_url: str,
    api_key: str,
) -> SurveyDefinition:
    """Fetch and parse a survey definition from the Qualtrics API.

    Uses GET /survey-definitions/{surveyId}.

    Args:
        survey_id: Qualtrics survey identifier (e.g. SV_xxx).
        base_url: Qualtrics API base URL (e.g. https://yul1.qualtrics.com/API/v3).
        api_key: Qualtrics API token.

    Returns:
        Parsed SurveyDefinition with all questions.

    Raises:
        requests.HTTPError: If the API returns a non-2xx status.
        requests.RequestException: On network errors.
    """
    url = f"{base_url}/survey-definitions/{survey_id}"
    headers = {
        "X-API-TOKEN": api_key,
        "Content-Type": "application/json",
    }

    logger.info("Fetching definition for survey %s", survey_id)
    response = requests.get(url, headers=headers, timeout=TIMEOUT_SECONDS)
    response.raise_for_status()

    payload = response.json()
    result = payload["result"]

    questions = [
        Question(
            question_id=qid,
            question_text=q.get("QuestionText", ""),
            question_type=q.get("QuestionType", ""),
            question_name=q.get("DataExportTag"),
        )
        for qid, q in result.get("Questions", {}).items()
    ]

    return SurveyDefinition(
        survey_id=survey_id,
        survey_name=result.get("SurveyName", ""),
        questions=questions,
    )
