"""
Tests for intake confirmation SMS sending.

Verifies that send_sms() uses messaging_service_sid (not from_number)
and handles missing credentials and Twilio errors correctly.
All Twilio calls are mocked -- no credentials needed.

Usage from project root:
    poetry run pytest gcp/tests/test_intake_confirmation.py -v

Note on module loading: both run_intake_confirmation and
run_followup_scheduling expose a `main` module. To avoid Python's
module cache returning the wrong one, we load intake's main.py
explicitly via importlib under the alias `intake_main`.
"""

import importlib.util
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

_INTAKE_MAIN_PATH = (
    Path(__file__).resolve().parent.parent
    / "cloud_run_functions"
    / "run_intake_confirmation"
    / "main.py"
)


def _load_intake_main():
    """Load run_intake_confirmation/main.py as 'intake_main'."""
    if "intake_main" in sys.modules:
        return sys.modules["intake_main"]
    spec = importlib.util.spec_from_file_location(
        "intake_main", _INTAKE_MAIN_PATH
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules["intake_main"] = module
    spec.loader.exec_module(module)
    return module


# Load once at import time so patches resolve against the cached module.
intake_main = _load_intake_main()


# -- Twilio send_sms tests -------------------------------------------
class TestSendSms:
    """Verify send_sms() uses messaging_service_sid, not from_number."""

    def test_missing_credentials_returns_false(self):
        """Empty messaging_service_sid -> False, no Twilio call."""
        original = intake_main.TWILIO_MESSAGING_SERVICE_SID
        intake_main.TWILIO_MESSAGING_SERVICE_SID = ""
        try:
            result = intake_main.send_sms("+18777804236", "Test body")
            assert result is False
        finally:
            intake_main.TWILIO_MESSAGING_SERVICE_SID = original

    @patch("intake_main.TWILIO_ACCOUNT_SID", "AC_test")
    @patch("intake_main.TWILIO_AUTH_TOKEN", "token_test")
    @patch("intake_main.TWILIO_MESSAGING_SERVICE_SID", "MG_test")
    def test_send_returns_true(self):
        """Successful send returns True and uses messaging_service_sid."""
        with patch("twilio.rest.Client") as MockClient:
            mock_message = MagicMock()
            mock_message.sid = "SM_test_123"
            mock_message.status = "sent"
            MockClient.return_value.messages.create.return_value = mock_message

            result = intake_main.send_sms("+18777804236", "Test body")

            assert result is True
            call_kwargs = (
                MockClient.return_value.messages.create.call_args.kwargs
            )
            assert call_kwargs.get("messaging_service_sid") == "MG_test"
            assert "from_" not in call_kwargs

    @patch("intake_main.TWILIO_ACCOUNT_SID", "AC_test")
    @patch("intake_main.TWILIO_AUTH_TOKEN", "token_test")
    @patch("intake_main.TWILIO_MESSAGING_SERVICE_SID", "MG_test")
    def test_twilio_error_returns_false(self):
        """Twilio exception -> False, does not re-raise."""
        with patch("twilio.rest.Client") as MockClient:
            MockClient.return_value.messages.create.side_effect = Exception(
                "Twilio unavailable"
            )

            result = intake_main.send_sms("+18777804236", "Test body")

            assert result is False
