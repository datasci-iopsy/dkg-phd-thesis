"""Tests for scripts/qualtrics/client.py.

All tests mock requests.get; no network access required.
"""

from unittest.mock import MagicMock, patch

import pytest
import requests
from client import Question, SurveyDefinition, fetch_survey_definition

BASE_URL = "https://yul1.qualtrics.com/API/v3"
API_KEY = "test-key"
SURVEY_ID = "SV_test123"


def _mock_response(payload: dict, status_code: int = 200) -> MagicMock:
    mock = MagicMock()
    mock.status_code = status_code
    mock.json.return_value = payload
    if status_code >= 400:
        mock.raise_for_status.side_effect = requests.HTTPError(response=mock)
    else:
        mock.raise_for_status.return_value = None
    return mock


@pytest.fixture()
def api_payload() -> dict:
    return {
        "result": {
            "SurveyName": "Followup Survey 1",
            "Questions": {
                "QID1": {
                    "QuestionText": "How are you feeling?",
                    "QuestionType": "MC",
                    "DataExportTag": "feeling",
                },
                "QID2": {
                    "QuestionText": "Rate your energy level.",
                    "QuestionType": "Slider",
                    "DataExportTag": "energy",
                },
            },
        }
    }


class TestFetchSurveyDefinition:
    def test_returns_survey_definition(self, api_payload: dict) -> None:
        with patch("client.requests.get") as mock_get:
            mock_get.return_value = _mock_response(api_payload)
            result = fetch_survey_definition(SURVEY_ID, BASE_URL, API_KEY)
        assert isinstance(result, SurveyDefinition)

    def test_survey_id_and_name(self, api_payload: dict) -> None:
        with patch("client.requests.get") as mock_get:
            mock_get.return_value = _mock_response(api_payload)
            result = fetch_survey_definition(SURVEY_ID, BASE_URL, API_KEY)
        assert result.survey_id == SURVEY_ID
        assert result.survey_name == "Followup Survey 1"

    def test_question_count(self, api_payload: dict) -> None:
        with patch("client.requests.get") as mock_get:
            mock_get.return_value = _mock_response(api_payload)
            result = fetch_survey_definition(SURVEY_ID, BASE_URL, API_KEY)
        assert len(result.questions) == 2

    def test_question_fields(self, api_payload: dict) -> None:
        with patch("client.requests.get") as mock_get:
            mock_get.return_value = _mock_response(api_payload)
            result = fetch_survey_definition(SURVEY_ID, BASE_URL, API_KEY)
        by_id = {q.question_id: q for q in result.questions}
        q1 = by_id["QID1"]
        assert q1.question_text == "How are you feeling?"
        assert q1.question_type == "MC"
        assert q1.question_name == "feeling"

    def test_question_without_export_tag(self, api_payload: dict) -> None:
        del api_payload["result"]["Questions"]["QID1"]["DataExportTag"]
        with patch("client.requests.get") as mock_get:
            mock_get.return_value = _mock_response(api_payload)
            result = fetch_survey_definition(SURVEY_ID, BASE_URL, API_KEY)
        by_id = {q.question_id: q for q in result.questions}
        assert by_id["QID1"].question_name is None

    def test_raises_on_http_error(self) -> None:
        with patch("client.requests.get") as mock_get:
            mock_get.return_value = _mock_response({}, status_code=401)
            with pytest.raises(requests.HTTPError):
                fetch_survey_definition(SURVEY_ID, BASE_URL, API_KEY)

    def test_calls_correct_url(self, api_payload: dict) -> None:
        with patch("client.requests.get") as mock_get:
            mock_get.return_value = _mock_response(api_payload)
            fetch_survey_definition(SURVEY_ID, BASE_URL, API_KEY)
        called_url = mock_get.call_args[0][0]
        assert called_url == f"{BASE_URL}/survey-definitions/{SURVEY_ID}"

    def test_sends_api_token_header(self, api_payload: dict) -> None:
        with patch("client.requests.get") as mock_get:
            mock_get.return_value = _mock_response(api_payload)
            fetch_survey_definition(SURVEY_ID, BASE_URL, API_KEY)
        headers = mock_get.call_args[1]["headers"]
        assert headers["X-API-TOKEN"] == API_KEY

    def test_empty_questions_block(self) -> None:
        payload = {"result": {"SurveyName": "Empty", "Questions": {}}}
        with patch("client.requests.get") as mock_get:
            mock_get.return_value = _mock_response(payload)
            result = fetch_survey_definition(SURVEY_ID, BASE_URL, API_KEY)
        assert result.questions == []


class TestQuestion:
    def test_question_name_optional(self) -> None:
        q = Question(
            question_id="QID1",
            question_text="Hello?",
            question_type="TE",
        )
        assert q.question_name is None

    def test_question_fields_stored(self) -> None:
        q = Question(
            question_id="QID5",
            question_text="Rate 1-5.",
            question_type="Slider",
            question_name="rating",
        )
        assert q.question_id == "QID5"
        assert q.question_text == "Rate 1-5."
        assert q.question_type == "Slider"
        assert q.question_name == "rating"
