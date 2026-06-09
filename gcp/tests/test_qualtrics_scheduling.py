"""Tests for run_qualtrics_scheduling: Connect routing and normal-path regression.

Covers:
  - _is_connect_participant discriminator (unit)
  - ConnectParticipantData model validation
  - extract_connect_participant_data validation (unit)
  - qualtrics_webhook_handler Connect path (mocked BQ + Pub/Sub)
  - qualtrics_webhook_handler normal path regression (mocked BQ + Pub/Sub)

All GCP and Pub/Sub calls are mocked -- no credentials needed.

Usage from project root:
    uv run pytest gcp/tests/test_qualtrics_scheduling.py -v
"""

from __future__ import annotations

import importlib.util
import json
from datetime import date
from pathlib import Path
from unittest.mock import patch

import pytest
from flask import Flask
from models.participant import ConnectParticipantData
from utils import validation_utils

# ---------------------------------------------------------------------------
# Load run_qualtrics_scheduling/main.py via importlib.
# fn3's dir is at sys.path[0] (last insert(0,...) in conftest), so
# `from main import ...` resolves to fn3. Load fn1 explicitly.
# ---------------------------------------------------------------------------

_FN1_DIR = (
    Path(__file__).parent.parent
    / "cloud_run_functions"
    / "run_qualtrics_scheduling"
)
_fn1_spec = importlib.util.spec_from_file_location(
    "run_qualtrics_scheduling_main", _FN1_DIR / "main.py"
)
_fn1_module = importlib.util.module_from_spec(_fn1_spec)
_fn1_spec.loader.exec_module(_fn1_module)

qualtrics_webhook_handler = _fn1_module.qualtrics_webhook_handler
_is_connect_participant = _fn1_module._is_connect_participant

_app = Flask(__name__)
FIXTURES_DIR = Path(__file__).resolve().parent / "fixtures"


def _load_fixture(name: str) -> dict:
    return json.loads((FIXTURES_DIR / name).read_text())


def _make_request(payload: dict):
    return _app.test_request_context(
        "/webhook",
        method="POST",
        content_type="application/json",
        data=json.dumps(payload),
    )


# ---------------------------------------------------------------------------
# _is_connect_participant discriminator
# ---------------------------------------------------------------------------


class TestIsConnectParticipant:
    """Verify the 32-hex discriminator for Connect routing."""

    def test_32hex_lowercase_is_connect(self):
        assert (
            _is_connect_participant("aabbccdd11223344aabbccdd11223344") is True
        )

    def test_32hex_uppercase_is_connect(self):
        assert (
            _is_connect_participant("AABBCCDD11223344AABBCCDD11223344") is True
        )

    def test_32hex_mixed_case_is_connect(self):
        assert (
            _is_connect_participant("aAbBcCdD11223344AaBbCcDd11223344") is True
        )

    def test_31_chars_not_connect(self):
        assert (
            _is_connect_participant("aabbccdd11223344aabbccdd1122334") is False
        )

    def test_33_chars_not_connect(self):
        assert (
            _is_connect_participant("aabbccdd11223344aabbccdd112233445")
            is False
        )

    def test_non_hex_chars_not_connect(self):
        assert (
            _is_connect_participant("zabbccdd11223344aabbccdd11223344") is False
        )

    def test_none_not_connect(self):
        assert _is_connect_participant(None) is False

    def test_blank_not_connect(self):
        assert _is_connect_participant("") is False

    def test_underscore_prefix_not_connect(self):
        # Snowball IDs like "dkgdkgdkgdkgdkgdkgdkgdkg" are not 32-hex
        assert (
            _is_connect_participant("test_aabbccdd11223344aabbccdd112") is False
        )


# ---------------------------------------------------------------------------
# ConnectParticipantData model
# ---------------------------------------------------------------------------


class TestConnectParticipantData:
    """Verify ConnectParticipantData model construction and validation."""

    def test_constructs_with_required_fields(self):
        p = ConnectParticipantData(
            response_id="R_connect_test",
            connect_id="aabbccdd11223344aabbccdd11223344",
            selected_date=date(2026, 6, 10),
            timezone="US/Eastern",
            consent_given=True,
        )
        assert p.response_id == "R_connect_test"
        assert p.connect_id == "aabbccdd11223344aabbccdd11223344"
        assert p.work_shift is None

    def test_no_phone_field(self):
        p = ConnectParticipantData(
            response_id="R_connect_test",
            connect_id="aabbccdd11223344aabbccdd11223344",
            selected_date=date(2026, 6, 10),
            timezone="US/Eastern",
            consent_given=True,
        )
        assert not hasattr(p, "phone")

    def test_consent_false_raises(self):
        with pytest.raises(ValueError):
            ConnectParticipantData(
                response_id="R_connect_test",
                connect_id="aabbccdd11223344aabbccdd11223344",
                selected_date=date(2026, 6, 10),
                timezone="US/Eastern",
                consent_given=False,
            )

    def test_work_shift_optional(self):
        p = ConnectParticipantData(
            response_id="R_connect_test",
            connect_id="aabbccdd11223344aabbccdd11223344",
            selected_date=date(2026, 6, 10),
            timezone="US/Eastern",
            consent_given=True,
            work_shift="first_shift",
        )
        assert p.work_shift == "first_shift"


# ---------------------------------------------------------------------------
# extract_connect_participant_data
# ---------------------------------------------------------------------------


class TestExtractConnectParticipantData:
    """Verify the Connect validation helper."""

    @pytest.fixture
    def connect_fixture(self) -> dict:
        return _load_fixture("connect_web_service_payload.json")

    def test_valid_payload_returns_participant(self, connect_fixture):
        from models.qualtrics import WebServicePayload

        payload = WebServicePayload.model_validate(connect_fixture)
        participant = validation_utils.extract_connect_participant_data(payload)
        assert participant is not None
        assert participant.connect_id == "aabbccdd11223344aabbccdd11223344"
        assert participant.timezone == "US/Eastern"
        assert participant.selected_date == date(2026, 6, 10)

    def test_no_consent_returns_none(self, connect_fixture):
        from models.qualtrics import WebServicePayload

        connect_fixture["CONSENT"] = "No"
        payload = WebServicePayload.model_validate(connect_fixture)
        assert (
            validation_utils.extract_connect_participant_data(payload) is None
        )

    def test_missing_selected_date_returns_none(self, connect_fixture):
        from models.qualtrics import WebServicePayload

        connect_fixture["SELECTED_DATE"] = None
        payload = WebServicePayload.model_validate(connect_fixture)
        assert (
            validation_utils.extract_connect_participant_data(payload) is None
        )

    def test_missing_timezone_returns_none(self, connect_fixture):
        from models.qualtrics import WebServicePayload

        connect_fixture["TIMEZONE"] = None
        payload = WebServicePayload.model_validate(connect_fixture)
        assert (
            validation_utils.extract_connect_participant_data(payload) is None
        )

    def test_invalid_date_format_returns_none(self, connect_fixture):
        from models.qualtrics import WebServicePayload

        connect_fixture["SELECTED_DATE"] = "June 10 2026"
        payload = WebServicePayload.model_validate(connect_fixture)
        assert (
            validation_utils.extract_connect_participant_data(payload) is None
        )


# ---------------------------------------------------------------------------
# Handler integration tests
# ---------------------------------------------------------------------------


class TestQualtricWebhookHandlerConnect:
    """Connect routing branch: mocked BQ + Pub/Sub, real validation."""

    @pytest.fixture
    def connect_payload(self) -> dict:
        return _load_fixture("connect_web_service_payload.json")

    @pytest.fixture
    def normal_payload(self) -> dict:
        return _load_fixture("web_service_payload.json")

    def test_connect_participant_routes_to_connect_path(self, connect_payload):
        with (
            patch.object(
                _fn1_module, "insert_survey_response", return_value=True
            ),
            patch.object(
                _fn1_module,
                "publish_connect_scheduling",
                return_value="msg-id-connect",
            ) as mock_connect_pub,
            patch.object(
                _fn1_module, "publish_intake_processed"
            ) as mock_intake_pub,
        ):
            with _make_request(connect_payload):
                from flask import request

                response, status = qualtrics_webhook_handler(request)

        assert status == 200
        body = json.loads(response.get_data(as_text=True))
        assert body["status"] == "success"
        assert body["path"] == "connect"
        assert body["published"] is True
        mock_connect_pub.assert_called_once()
        mock_intake_pub.assert_not_called()

    def test_connect_publish_failure_returns_200_published_false(
        self, connect_payload
    ):
        with (
            patch.object(
                _fn1_module, "insert_survey_response", return_value=True
            ),
            patch.object(
                _fn1_module, "publish_connect_scheduling", return_value=None
            ),
            patch.object(
                _fn1_module, "publish_intake_processed"
            ) as mock_intake,
        ):
            with _make_request(connect_payload):
                from flask import request

                response, status = qualtrics_webhook_handler(request)

        assert status == 200
        body = json.loads(response.get_data(as_text=True))
        assert body["published"] is False
        mock_intake.assert_not_called()

    def test_connect_no_consent_returns_400(self, connect_payload):
        connect_payload["CONSENT"] = "No"
        with (
            patch.object(
                _fn1_module, "insert_survey_response", return_value=True
            ),
            patch.object(
                _fn1_module, "publish_connect_scheduling"
            ) as mock_connect,
        ):
            with _make_request(connect_payload):
                from flask import request

                _response, status = qualtrics_webhook_handler(request)

        assert status == 400
        mock_connect.assert_not_called()

    def test_normal_participant_routes_to_twilio_path(self, normal_payload):
        """Normal (snowball) participant must NOT trigger the Connect branch."""
        with (
            patch.object(
                _fn1_module, "insert_survey_response", return_value=True
            ),
            patch.object(
                _fn1_module,
                "publish_intake_processed",
                return_value="msg-id-twilio",
            ) as mock_intake_pub,
            patch.object(
                _fn1_module, "publish_connect_scheduling"
            ) as mock_connect_pub,
        ):
            with _make_request(normal_payload):
                from flask import request

                response, status = qualtrics_webhook_handler(request)

        assert status == 200
        body = json.loads(response.get_data(as_text=True))
        assert body["status"] == "success"
        assert "path" not in body
        mock_intake_pub.assert_called_once()
        mock_connect_pub.assert_not_called()

    def test_normal_participant_missing_phone_returns_400(self, normal_payload):
        """Missing phone on normal (non-Connect) participant returns 400."""
        normal_payload["PHONE"] = ""
        with patch.object(
            _fn1_module, "insert_survey_response", return_value=True
        ):
            with _make_request(normal_payload):
                from flask import request

                _response, status = qualtrics_webhook_handler(request)

        assert status == 400
