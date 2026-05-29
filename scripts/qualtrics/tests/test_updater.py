"""Tests for scripts/qualtrics/updater.py.

All tests mock requests; no network access required.
"""

from unittest.mock import MagicMock, patch

import pytest
import requests
from changes import QuestionChange
from updater import (
    fetch_question,
    put_question,
    update_question_text,
    verify_question_text,
)

BASE_URL = "https://yul1.qualtrics.com/API/v3"
API_KEY = "test-key"
SURVEY_ID = "SV_test123"
QUESTION_ID = "QID1"

QUESTION_BODY = {
    "QuestionText": "Old question text.",
    "QuestionType": "MC",
    "DataExportTag": "PF2",
    "Choices": {"1": {"Display": "Never"}, "2": {"Display": "Sometimes"}},
}


def _mock_response(payload: dict, status_code: int = 200) -> MagicMock:
    mock = MagicMock()
    mock.status_code = status_code
    mock.json.return_value = payload
    if status_code >= 400:
        mock.raise_for_status.side_effect = requests.HTTPError(response=mock)
    else:
        mock.raise_for_status.return_value = None
    return mock


class TestFetchQuestion:
    def test_returns_question_body(self) -> None:
        with patch("updater.requests.get") as mock_get:
            mock_get.return_value = _mock_response({"result": QUESTION_BODY})
            result = fetch_question(SURVEY_ID, QUESTION_ID, BASE_URL, API_KEY)
        assert result["QuestionText"] == "Old question text."

    def test_calls_correct_url(self) -> None:
        with patch("updater.requests.get") as mock_get:
            mock_get.return_value = _mock_response({"result": QUESTION_BODY})
            fetch_question(SURVEY_ID, QUESTION_ID, BASE_URL, API_KEY)
        called_url = mock_get.call_args[0][0]
        expected = (
            f"{BASE_URL}/survey-definitions/{SURVEY_ID}/questions/{QUESTION_ID}"
        )
        assert called_url == expected

    def test_sends_api_token_header(self) -> None:
        with patch("updater.requests.get") as mock_get:
            mock_get.return_value = _mock_response({"result": QUESTION_BODY})
            fetch_question(SURVEY_ID, QUESTION_ID, BASE_URL, API_KEY)
        headers = mock_get.call_args[1]["headers"]
        assert headers["X-API-TOKEN"] == API_KEY

    def test_raises_on_http_error(self) -> None:
        with patch("updater.requests.get") as mock_get:
            mock_get.return_value = _mock_response({}, status_code=403)
            with pytest.raises(requests.HTTPError):
                fetch_question(SURVEY_ID, QUESTION_ID, BASE_URL, API_KEY)


class TestPutQuestion:
    def test_calls_correct_url(self) -> None:
        with patch("updater.requests.put") as mock_put:
            mock_put.return_value = _mock_response({"result": "OK"})
            put_question(
                SURVEY_ID, QUESTION_ID, QUESTION_BODY, BASE_URL, API_KEY
            )
        called_url = mock_put.call_args[0][0]
        expected = (
            f"{BASE_URL}/survey-definitions/{SURVEY_ID}/questions/{QUESTION_ID}"
        )
        assert called_url == expected

    def test_sends_question_body_as_json(self) -> None:
        with patch("updater.requests.put") as mock_put:
            mock_put.return_value = _mock_response({"result": "OK"})
            put_question(
                SURVEY_ID, QUESTION_ID, QUESTION_BODY, BASE_URL, API_KEY
            )
        sent_json = mock_put.call_args[1]["json"]
        assert sent_json == QUESTION_BODY

    def test_sends_api_token_header(self) -> None:
        with patch("updater.requests.put") as mock_put:
            mock_put.return_value = _mock_response({"result": "OK"})
            put_question(
                SURVEY_ID, QUESTION_ID, QUESTION_BODY, BASE_URL, API_KEY
            )
        headers = mock_put.call_args[1]["headers"]
        assert headers["X-API-TOKEN"] == API_KEY

    def test_raises_on_http_error(self) -> None:
        with patch("updater.requests.put") as mock_put:
            mock_put.return_value = _mock_response({}, status_code=500)
            with pytest.raises(requests.HTTPError):
                put_question(
                    SURVEY_ID, QUESTION_ID, QUESTION_BODY, BASE_URL, API_KEY
                )


class TestUpdateQuestionText:
    def _mock_get_put(self, old_text: str = "Old question text."):
        body = {**QUESTION_BODY, "QuestionText": old_text}
        return (
            _mock_response({"result": body}),
            _mock_response({"result": "OK"}),
        )

    def test_full_replacement_sends_new_text(self) -> None:
        change = QuestionChange(
            survey_id=SURVEY_ID,
            question_id=QUESTION_ID,
            replace_text="New question text.",
        )
        get_resp, put_resp = self._mock_get_put()
        with (
            patch("updater.requests.get", return_value=get_resp),
            patch("updater.requests.put", return_value=put_resp) as mock_put,
        ):
            update_question_text(change, BASE_URL, API_KEY)
        sent_body = mock_put.call_args[1]["json"]
        assert sent_body["QuestionText"] == "New question text."

    def test_find_replace_modifies_only_matched_substring(self) -> None:
        change = QuestionChange(
            survey_id=SURVEY_ID,
            question_id=QUESTION_ID,
            find_text="Old",
            replace_text="Updated",
        )
        get_resp, put_resp = self._mock_get_put(old_text="Old question text.")
        with (
            patch("updater.requests.get", return_value=get_resp),
            patch("updater.requests.put", return_value=put_resp) as mock_put,
        ):
            update_question_text(change, BASE_URL, API_KEY)
        sent_body = mock_put.call_args[1]["json"]
        assert sent_body["QuestionText"] == "Updated question text."

    def test_find_replace_raises_when_find_text_not_found(self) -> None:
        change = QuestionChange(
            survey_id=SURVEY_ID,
            question_id=QUESTION_ID,
            find_text="Does not exist",
            replace_text="New",
        )
        get_resp, put_resp = self._mock_get_put(old_text="Old question text.")
        with (
            patch("updater.requests.get", return_value=get_resp),
            patch("updater.requests.put", return_value=put_resp),
        ):
            with pytest.raises(ValueError, match="Does not exist"):
                update_question_text(change, BASE_URL, API_KEY)

    def test_preserves_other_question_fields(self) -> None:
        change = QuestionChange(
            survey_id=SURVEY_ID,
            question_id=QUESTION_ID,
            replace_text="New text.",
        )
        get_resp, put_resp = self._mock_get_put()
        with (
            patch("updater.requests.get", return_value=get_resp),
            patch("updater.requests.put", return_value=put_resp) as mock_put,
        ):
            update_question_text(change, BASE_URL, API_KEY)
        sent_body = mock_put.call_args[1]["json"]
        assert sent_body["QuestionType"] == "MC"
        assert sent_body["DataExportTag"] == "PF2"

    def test_does_not_put_when_find_text_missing(self) -> None:
        change = QuestionChange(
            survey_id=SURVEY_ID,
            question_id=QUESTION_ID,
            find_text="missing phrase",
            replace_text="replacement",
        )
        get_resp, put_resp = self._mock_get_put(
            old_text="Something else entirely."
        )
        with (
            patch("updater.requests.get", return_value=get_resp),
            patch("updater.requests.put", return_value=put_resp) as mock_put,
        ):
            with pytest.raises(ValueError):
                update_question_text(change, BASE_URL, API_KEY)
        mock_put.assert_not_called()


class TestVerifyQuestionText:
    def test_full_replace_returns_true_when_matches(self) -> None:
        change = QuestionChange(
            survey_id=SURVEY_ID,
            question_id=QUESTION_ID,
            replace_text="New text.",
        )
        body = {**QUESTION_BODY, "QuestionText": "New text."}
        with patch(
            "updater.requests.get",
            return_value=_mock_response({"result": body}),
        ):
            ok, _ = verify_question_text(change, BASE_URL, API_KEY)
        assert ok is True

    def test_full_replace_returns_false_when_differs(self) -> None:
        change = QuestionChange(
            survey_id=SURVEY_ID,
            question_id=QUESTION_ID,
            replace_text="Expected.",
        )
        body = {**QUESTION_BODY, "QuestionText": "Actual different text."}
        with patch(
            "updater.requests.get",
            return_value=_mock_response({"result": body}),
        ):
            ok, _ = verify_question_text(change, BASE_URL, API_KEY)
        assert ok is False

    def test_returns_current_text_on_mismatch(self) -> None:
        change = QuestionChange(
            survey_id=SURVEY_ID,
            question_id=QUESTION_ID,
            replace_text="Expected.",
        )
        body = {**QUESTION_BODY, "QuestionText": "Actual text."}
        with patch(
            "updater.requests.get",
            return_value=_mock_response({"result": body}),
        ):
            _, current = verify_question_text(change, BASE_URL, API_KEY)
        assert current == "Actual text."

    def test_find_replace_returns_true_when_new_phrase_present(self) -> None:
        change = QuestionChange(
            survey_id=SURVEY_ID,
            question_id=QUESTION_ID,
            find_text="Since starting work today",
            replace_text="Since the first survey check-in",
        )
        body = {
            **QUESTION_BODY,
            "QuestionText": "<b>Since the first survey check-in</b>, how many meetings?",
        }
        with patch(
            "updater.requests.get",
            return_value=_mock_response({"result": body}),
        ):
            ok, _ = verify_question_text(change, BASE_URL, API_KEY)
        assert ok is True

    def test_find_replace_returns_false_when_old_phrase_still_present(
        self,
    ) -> None:
        change = QuestionChange(
            survey_id=SURVEY_ID,
            question_id=QUESTION_ID,
            find_text="Since starting work today",
            replace_text="Since the first survey check-in",
        )
        body = {
            **QUESTION_BODY,
            "QuestionText": "<b>Since starting work today</b>, how many meetings?",
        }
        with patch(
            "updater.requests.get",
            return_value=_mock_response({"result": body}),
        ):
            ok, _ = verify_question_text(change, BASE_URL, API_KEY)
        assert ok is False
