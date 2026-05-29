"""Qualtrics Survey Definitions API updater.

Mutates survey question text via GET then PUT on individual questions.
"""

import logging

import requests

from changes import QuestionChange

logger = logging.getLogger(__name__)

TIMEOUT_SECONDS = 30


def _headers(api_key: str) -> dict:
    return {"X-API-TOKEN": api_key, "Content-Type": "application/json"}


def fetch_question(
    survey_id: str, question_id: str, base_url: str, api_key: str
) -> dict:
    url = f"{base_url}/survey-definitions/{survey_id}/questions/{question_id}"
    response = requests.get(
        url, headers=_headers(api_key), timeout=TIMEOUT_SECONDS
    )
    response.raise_for_status()
    return response.json()["result"]


def put_question(
    survey_id: str,
    question_id: str,
    question_body: dict,
    base_url: str,
    api_key: str,
) -> None:
    url = f"{base_url}/survey-definitions/{survey_id}/questions/{question_id}"
    response = requests.put(
        url,
        headers=_headers(api_key),
        json=question_body,
        timeout=TIMEOUT_SECONDS,
    )
    response.raise_for_status()


def update_question_text(
    change: QuestionChange, base_url: str, api_key: str
) -> None:
    body = fetch_question(
        change.survey_id, change.question_id, base_url, api_key
    )
    current_text = body["QuestionText"]

    if change.find_text is None:
        new_text = change.replace_text
    else:
        if change.find_text not in current_text:
            raise ValueError(
                f"find_text not found in {change.survey_id}/{change.question_id}: {change.find_text!r}"
            )
        new_text = current_text.replace(change.find_text, change.replace_text)

    updated_body = {**body, "QuestionText": new_text}
    put_question(
        change.survey_id, change.question_id, updated_body, base_url, api_key
    )
    logger.info(
        "Updated %s/%s (%s)",
        change.survey_id,
        change.question_id,
        change.description,
    )


def verify_question_text(
    change: QuestionChange, base_url: str, api_key: str
) -> tuple[bool, str]:
    body = fetch_question(
        change.survey_id, change.question_id, base_url, api_key
    )
    current_text = body["QuestionText"]

    if change.find_text is None:
        ok = current_text == change.replace_text
    else:
        ok = (
            change.replace_text in current_text
            and change.find_text not in current_text
        )

    return ok, current_text
