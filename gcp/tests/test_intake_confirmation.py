"""
Tests for intake confirmation SMS sending.

Verifies that send_sms() uses messaging_service_sid (not from_number)
and handles missing credentials and Twilio errors correctly.
All Twilio calls are mocked -- no credentials needed.

Usage from project root:
    uv run pytest gcp/tests/test_intake_confirmation.py -v

Note on module loading: both run_intake_confirmation and
run_followup_scheduling expose a `main` module. To avoid Python's
module cache returning the wrong one, we load intake's main.py
explicitly via importlib under the alias `intake_main`.
"""

import base64
import importlib.util
import json
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


# -- format_sms_body tests (Slice B) ---------------------------------
class TestFormatSmsBody:
    """Verify format_sms_body uses generic shift language with no
    hardcoded survey times.
    """

    def test_none_work_shift_uses_generic_language(self):
        """work_shift=None -> 'your work day' phrasing."""
        from datetime import date

        body = intake_main.format_sms_body(date(2026, 6, 1), "US/Central", None)
        assert "your work day" in body

    def test_none_work_shift_has_no_hardcoded_times(self):
        """Legacy path must not expose hardcoded time strings."""
        from datetime import date

        body = intake_main.format_sms_body(date(2026, 6, 1), "US/Central", None)
        assert "9:00" not in body
        assert "1:00" not in body
        assert "5:00" not in body

    def test_first_shift_label_in_body(self):
        """work_shift='first_shift' -> 'First Shift' in body."""
        from datetime import date

        body = intake_main.format_sms_body(
            date(2026, 6, 1), "US/Central", "first_shift"
        )
        assert "First Shift" in body

    def test_body_includes_selected_date(self):
        """Participant's selected date must appear in the confirmation."""
        from datetime import date

        body = intake_main.format_sms_body(
            date(2026, 6, 1), "US/Central", "first_shift"
        )
        assert "June 01, 2026" in body


# -- Work shift forwarding tests (Slice A) ---------------------------
_FAR_FUTURE_DATE = "2099-06-01"


class TestWorkShiftForwarding:
    """work_shift from IntakeProcessedMessage must arrive unchanged in
    the FollowupSchedulingMessage published by fn2's handler.
    """

    def _make_cloud_event(self, message_data: dict) -> MagicMock:
        encoded = base64.b64encode(json.dumps(message_data).encode()).decode()
        event = MagicMock()
        event.data = {"message": {"data": encoded}}
        return event

    @patch("intake_main.publish_followup_scheduling", return_value="msg_123")
    @patch("intake_main.update_processed_flag", return_value=True)
    @patch("intake_main.send_sms", return_value=True)
    @patch("intake_main.is_already_processed", return_value=False)
    @patch("intake_main.decrypt_phone", return_value="+18777804236")
    @patch("intake_main.bigquery.Client")
    @patch("intake_main.config")
    def test_work_shift_forwarded_to_followup_message(
        self,
        mock_config,
        mock_bq,
        mock_decrypt,
        mock_processed,
        mock_sms,
        mock_update,
        mock_publish,
    ):
        """work_shift='first_shift' from intake message appears in
        the FollowupSchedulingMessage passed to publish_followup_scheduling.
        """
        from shared.utils.pubsub_utils import FollowupSchedulingMessage
        from shared.utils.crypto_utils import encrypt_phone

        encrypted = encrypt_phone("+18777804236")
        event = self._make_cloud_event(
            {
                "response_id": "R_shift_fwd_test",
                "phone": encrypted,
                "selected_date": _FAR_FUTURE_DATE,
                "timezone": "US/Central",
                "work_shift": "first_shift",
            }
        )

        intake_main.intake_confirmation_handler(event)

        mock_publish.assert_called_once()
        published_msg = mock_publish.call_args[0][0]
        assert isinstance(published_msg, FollowupSchedulingMessage)
        assert published_msg.work_shift == "first_shift"

    @patch("intake_main.publish_followup_scheduling", return_value="msg_456")
    @patch("intake_main.update_processed_flag", return_value=True)
    @patch("intake_main.send_sms", return_value=True)
    @patch("intake_main.is_already_processed", return_value=False)
    @patch("intake_main.decrypt_phone", return_value="+18777804236")
    @patch("intake_main.bigquery.Client")
    @patch("intake_main.config")
    def test_work_shift_none_forwarded(
        self,
        mock_config,
        mock_bq,
        mock_decrypt,
        mock_processed,
        mock_sms,
        mock_update,
        mock_publish,
    ):
        """None work_shift (existing participant path) also forwards
        without error.
        """
        from shared.utils.pubsub_utils import FollowupSchedulingMessage
        from shared.utils.crypto_utils import encrypt_phone

        encrypted = encrypt_phone("+18777804236")
        event = self._make_cloud_event(
            {
                "response_id": "R_none_shift_test",
                "phone": encrypted,
                "selected_date": _FAR_FUTURE_DATE,
                "timezone": "US/Central",
                # work_shift intentionally absent -> None
            }
        )

        intake_main.intake_confirmation_handler(event)

        mock_publish.assert_called_once()
        published_msg = mock_publish.call_args[0][0]
        assert isinstance(published_msg, FollowupSchedulingMessage)
        assert published_msg.work_shift is None
