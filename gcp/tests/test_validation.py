"""
Tests for validation_utils -- payload parsing and participant extraction.

Uses Flask's test request context to simulate incoming Web Service
task POSTs and the web_service_payload.json fixture for participant
extraction.

Usage from project root:
    poetry run pytest gcp/tests/test_validation.py -v
"""

import json
from datetime import date
from pathlib import Path

import pytest
from flask import Flask
from models.qualtrics import WebServicePayload
from utils.validation_utils import (
    extract_participant_data,
    extract_web_service_payload,
)

# -- Fixtures --------------------------------------------------------
FIXTURES_DIR = Path(__file__).resolve().parent / "fixtures"

# Minimal Flask app for building test request contexts
_app = Flask(__name__)


@pytest.fixture
def raw_web_service_json() -> dict:
    path = FIXTURES_DIR / "web_service_payload.json"
    return json.loads(path.read_text())


@pytest.fixture
def web_service_payload(raw_web_service_json) -> WebServicePayload:
    return WebServicePayload.model_validate(raw_web_service_json)


# -- extract_web_service_payload tests -------------------------------
class TestExtractWebServicePayload:
    """Verify Web Service task POST parsing and validation."""

    def test_valid_payload(self, raw_web_service_json):
        with _app.test_request_context(
            "/",
            method="POST",
            content_type="application/json",
            data=json.dumps(raw_web_service_json),
        ):
            from flask import request

            result = extract_web_service_payload(request)

        assert result is not None
        assert result.response_id == "R_2LObbbYBNZqyuhX"
        assert result.consent == "Yes"

    def test_rejects_empty_body(self):
        with _app.test_request_context(
            "/",
            method="POST",
            content_type="application/json",
            data="",
        ):
            from flask import request

            result = extract_web_service_payload(request)

        assert result is None

    def test_rejects_missing_required_field(self):
        """response_id is required -- missing it should fail."""
        payload = {"survey_id": "SV_test"}
        with _app.test_request_context(
            "/",
            method="POST",
            content_type="application/json",
            data=json.dumps(payload),
        ):
            from flask import request

            result = extract_web_service_payload(request)

        assert result is None

    def test_accepts_partial_payload(self):
        """Partial payloads (only required fields) should validate."""
        payload = {
            "response_id": "R_partial_001",
            "survey_id": "SV_test456",
        }
        with _app.test_request_context(
            "/",
            method="POST",
            content_type="application/json",
            data=json.dumps(payload),
        ):
            from flask import request

            result = extract_web_service_payload(request)

        assert result is not None
        assert result.response_id == "R_partial_001"
        assert result.consent is None
        assert result.PA1 is None

    def test_rejects_wrong_type(self, raw_web_service_json):
        raw_web_service_json["age"] = "not_a_number"
        with _app.test_request_context(
            "/",
            method="POST",
            content_type="application/json",
            data=json.dumps(raw_web_service_json),
        ):
            from flask import request

            result = extract_web_service_payload(request)

        assert result is None

    def test_rejects_malformed_json(self):
        with _app.test_request_context(
            "/",
            method="POST",
            content_type="application/json",
            data="{invalid json",
        ):
            from flask import request

            result = extract_web_service_payload(request)

        assert result is None


# -- extract_participant_data tests ----------------------------------
class TestExtractParticipantData:
    """Verify participant extraction from WebServicePayload."""

    def test_extracts_from_fixture(self, web_service_payload):
        participant = extract_participant_data(web_service_payload)

        assert participant is not None
        assert participant.response_id == "R_2LObbbYBNZqyuhX"
        assert participant.prolific_pid == "dkgdkgdkgdkgdkgdkgdkgdkg"
        assert participant.phone == "+18777804236"
        assert participant.selected_date == date(2025, 12, 26)
        assert participant.timezone == "US/Central"
        assert participant.consent_given is True

    def test_rejects_non_consent(self, raw_web_service_json):
        raw_web_service_json["consent"] = "No"
        payload = WebServicePayload.model_validate(raw_web_service_json)

        participant = extract_participant_data(payload)
        assert participant is None

    def test_rejects_none_consent(self):
        """Missing consent (None) should be rejected."""
        payload = WebServicePayload(response_id="R_test", survey_id="SV_test")
        participant = extract_participant_data(payload)
        assert participant is None

    def test_rejects_bad_phone(self, raw_web_service_json):
        raw_web_service_json["phone"] = "123"
        payload = WebServicePayload.model_validate(raw_web_service_json)

        participant = extract_participant_data(payload)
        assert participant is None

    def test_rejects_none_phone(self):
        """Missing phone (None) should be rejected."""
        payload = WebServicePayload(
            response_id="R_test",
            survey_id="SV_test",
            consent="Yes",
            prolific_pid="test_pid",
            timezone="US/Central",
            selected_date="12/26/2025",
        )
        participant = extract_participant_data(payload)
        assert participant is None

    def test_rejects_bad_date(self, raw_web_service_json):
        raw_web_service_json["selected_date"] = "not-a-date"
        payload = WebServicePayload.model_validate(raw_web_service_json)

        participant = extract_participant_data(payload)
        assert participant is None

    def test_rejects_none_selected_date(self):
        """Missing selected_date (None) should be rejected."""
        payload = WebServicePayload(
            response_id="R_test",
            survey_id="SV_test",
            consent="Yes",
            prolific_pid="test_pid",
            phone="8777804236",
            timezone="US/Central",
        )
        participant = extract_participant_data(payload)
        assert participant is None

    def test_rejects_none_timezone(self):
        """Missing timezone (None) should be rejected."""
        payload = WebServicePayload(
            response_id="R_test",
            survey_id="SV_test",
            consent="Yes",
            prolific_pid="test_pid",
            phone="8777804236",
            selected_date="12/26/2025",
        )
        participant = extract_participant_data(payload)
        assert participant is None

    def test_rejects_none_prolific_pid(self):
        """Missing prolific_pid (None) should be rejected."""
        payload = WebServicePayload(
            response_id="R_test",
            survey_id="SV_test",
            consent="Yes",
            phone="8777804236",
            timezone="US/Central",
            selected_date="12/26/2025",
        )
        participant = extract_participant_data(payload)
        assert participant is None

    def test_rejects_empty_timezone(self, raw_web_service_json):
        raw_web_service_json["timezone"] = ""
        payload = WebServicePayload.model_validate(raw_web_service_json)

        participant = extract_participant_data(payload)
        assert participant is None

    def test_rejects_blank_prolific_pid(self, raw_web_service_json):
        raw_web_service_json["prolific_pid"] = "   "
        payload = WebServicePayload.model_validate(raw_web_service_json)

        participant = extract_participant_data(payload)
        assert participant is None
