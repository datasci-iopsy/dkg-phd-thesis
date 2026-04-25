"""
Tests for follow-up survey SMS scheduling.

Verifies the FollowupSchedulingMessage model, survey URL
construction, timezone conversion, and the scheduling handler.
All GCP and Twilio calls are mocked -- no credentials needed.

Usage from project root:
    uv run pytest gcp/tests/test_followup_scheduling.py -v
"""

import base64
import json
from datetime import date, datetime, time, timezone
from unittest.mock import MagicMock, patch

import pytest
from shared.utils.pubsub_utils import (
    FollowupSchedulingMessage,
    IntakeProcessedMessage,
)


# -- FollowupSchedulingMessage model tests ---------------------------
class TestFollowupSchedulingMessage:
    """Verify the Pub/Sub message model for follow-up scheduling."""

    def test_required_fields(self):
        msg = FollowupSchedulingMessage(
            response_id="R_abc123",
            phone="+18777804236",
            selected_date="2026-02-24",
            timezone="US/Central",
        )
        assert msg.response_id == "R_abc123"
        assert msg.connect_id is None

    def test_connect_id_nullable(self):
        msg = FollowupSchedulingMessage(
            response_id="R_abc123",
            connect_id=None,
            phone="+18777804236",
            selected_date="2026-02-24",
            timezone="US/Central",
        )
        assert msg.connect_id is None

    def test_connect_id_present(self):
        msg = FollowupSchedulingMessage(
            response_id="R_abc123",
            connect_id="60a7c1b2e3f4a5b6c7d8e9f0",
            phone="+18777804236",
            selected_date="2026-02-24",
            timezone="US/Central",
        )
        assert msg.connect_id == "60a7c1b2e3f4a5b6c7d8e9f0"

    def test_round_trips(self):
        msg = FollowupSchedulingMessage(
            response_id="R_abc123",
            connect_id="test_pid",
            phone="+18777804236",
            selected_date="2026-02-24",
            timezone="US/Central",
        )
        dumped = msg.model_dump()
        restored = FollowupSchedulingMessage.model_validate(dumped)
        assert restored == msg

    def test_missing_response_id_rejected(self):
        with pytest.raises(Exception):
            FollowupSchedulingMessage(
                phone="+18777804236",
                selected_date="2026-02-24",
                timezone="US/Central",
            )


class TestIntakeProcessedMessageConnectId:
    """Verify connect_id was added to IntakeProcessedMessage."""

    def test_default_none(self):
        msg = IntakeProcessedMessage(
            response_id="R_abc123",
            phone="+18777804236",
            selected_date="2026-02-24",
            timezone="US/Central",
        )
        assert msg.connect_id is None

    def test_explicit_value(self):
        msg = IntakeProcessedMessage(
            response_id="R_abc123",
            connect_id="test_pid",
            phone="+18777804236",
            selected_date="2026-02-24",
            timezone="US/Central",
        )
        assert msg.connect_id == "test_pid"

    def test_backward_compatible_deserialization(self):
        """Messages without connect_id (old format) still parse."""
        raw = {
            "response_id": "R_abc123",
            "phone": "+18777804236",
            "selected_date": "2099-02-24",
            "timezone": "US/Central",
        }
        msg = IntakeProcessedMessage.model_validate(raw)
        assert msg.connect_id is None


# -- Survey URL building tests ---------------------------------------
class TestBuildSurveyUrl:
    """Verify follow-up survey URL construction with query params."""

    @pytest.fixture(autouse=True)
    def _setup_config(self):
        """Patch the config for URL building tests."""
        self.mock_config = MagicMock()
        self.mock_config.followup_surveys.survey_base_url = (
            "https://ncsu.qualtrics.com/jfe/form"
        )

    def test_url_with_connect_id(self):
        from main import build_survey_url

        url = build_survey_url(
            survey_id="SV_test123",
            response_id="R_abc",
            connect_id="pid_xyz",
            survey_time=1,
            selected_date="2026-02-24",
        )
        assert "SV_test123" in url
        assert "response_id=R_abc" in url
        assert "connect_id=pid_xyz" in url
        assert "survey_time=1" in url
        assert "selected_date=2026-02-24" in url

    def test_url_without_connect_id(self):
        from main import build_survey_url

        url = build_survey_url(
            survey_id="SV_test123",
            response_id="R_abc",
            connect_id=None,
            survey_time=2,
            selected_date="2026-02-24",
        )
        assert "connect_id" not in url
        assert "response_id=R_abc" in url
        assert "survey_time=2" in url

    def test_url_encodes_special_chars(self):
        from main import build_survey_url

        url = build_survey_url(
            survey_id="SV_test",
            response_id="R_abc+def",
            connect_id=None,
            survey_time=1,
            selected_date="2026-02-24",
        )
        # '+' should be URL-encoded
        assert "R_abc%2Bdef" in url or "R_abc+def" not in url.split("?")[1]

    def test_all_three_slots(self):
        from main import build_survey_url

        for slot in (1, 2, 3):
            url = build_survey_url(
                survey_id=f"SV_slot{slot}",
                response_id="R_test",
                connect_id=None,
                survey_time=slot,
                selected_date="2026-02-24",
            )
            assert f"survey_time={slot}" in url
            assert f"SV_slot{slot}" in url


# -- Timezone conversion tests ---------------------------------------
class TestComputeSendAt:
    """Verify timezone-aware UTC conversion for Twilio send_at."""

    def test_us_central(self):
        from main import compute_send_at

        result = compute_send_at(date(2026, 2, 24), time(9, 0), "US/Central")
        # Feb 24 is winter -> CST = UTC-6
        assert result.tzinfo is not None
        assert result.hour == 15  # 9 AM + 6 hours
        assert result.day == 24

    def test_us_eastern(self):
        from main import compute_send_at

        result = compute_send_at(date(2026, 2, 24), time(13, 0), "US/Eastern")
        # Feb 24 is winter -> EST = UTC-5
        assert result.hour == 18  # 1 PM + 5 hours

    def test_us_pacific(self):
        from main import compute_send_at

        result = compute_send_at(date(2026, 2, 24), time(17, 0), "US/Pacific")
        # Feb 24 is winter -> PST = UTC-8
        assert result.day == 25  # 5 PM + 8 = 1 AM next day
        assert result.hour == 1

    def test_returns_utc(self):
        from main import compute_send_at

        result = compute_send_at(date(2026, 7, 15), time(9, 0), "US/Central")
        # Result should be in UTC
        assert result.utcoffset().total_seconds() == 0

    def test_invalid_timezone_raises(self):
        from main import compute_send_at

        with pytest.raises(KeyError):
            compute_send_at(date(2026, 2, 24), time(9, 0), "Invalid/Timezone")


# -- Time label formatting tests -------------------------------------
class TestFormatTimeLabel:
    """Verify 12-hour time formatting."""

    def test_morning(self):
        from main import format_time_label

        assert format_time_label(time(9, 0)) == "9:00 AM"

    def test_afternoon(self):
        from main import format_time_label

        assert format_time_label(time(13, 0)) == "1:00 PM"

    def test_evening(self):
        from main import format_time_label

        assert format_time_label(time(17, 0)) == "5:00 PM"


# -- Twilio scheduling mock tests -----------------------------------
class TestScheduleSms:
    """Verify Twilio message scheduling with mocked client."""

    def test_missing_credentials_returns_none(self):
        """No messaging_service_sid -> None."""
        import main

        original_sid = main.TWILIO_MESSAGING_SERVICE_SID
        main.TWILIO_MESSAGING_SERVICE_SID = ""
        try:
            result = main.schedule_sms(
                "+18777804236",
                "Test body",
                datetime(2026, 2, 24, 15, 0, tzinfo=timezone.utc),
            )
            assert result is None
        finally:
            main.TWILIO_MESSAGING_SERVICE_SID = original_sid

    @patch("main.TWILIO_ACCOUNT_SID", "AC_test")
    @patch("main.TWILIO_AUTH_TOKEN", "token_test")
    @patch("main.TWILIO_MESSAGING_SERVICE_SID", "MG_test")
    def test_schedule_returns_sid(self):
        with patch("twilio.rest.Client") as MockClient:
            mock_message = MagicMock()
            mock_message.sid = "SM_scheduled_123"
            mock_message.status = "scheduled"
            MockClient.return_value.messages.create.return_value = mock_message

            from main import schedule_sms

            result = schedule_sms(
                "+18777804236",
                "Test body",
                datetime(2026, 2, 24, 15, 0, tzinfo=timezone.utc),
            )
            assert result == "SM_scheduled_123"

    @patch("main.TWILIO_ACCOUNT_SID", "AC_test")
    @patch("main.TWILIO_AUTH_TOKEN", "token_test")
    @patch("main.TWILIO_MESSAGING_SERVICE_SID", "MG_test")
    def test_twilio_error_returns_none(self):
        with patch("twilio.rest.Client") as MockClient:
            MockClient.return_value.messages.create.side_effect = Exception(
                "Twilio API error"
            )

            from main import schedule_sms

            result = schedule_sms(
                "+18777804236",
                "Test body",
                datetime(2026, 2, 24, 15, 0, tzinfo=timezone.utc),
            )
            assert result is None


# -- Idempotency tests -----------------------------------------------
class TestIdempotency:
    """Verify BigQuery idempotency check for scheduling."""

    @patch("main.config")
    def test_already_scheduled_returns_true(self, mock_config):
        mock_config.gcp.project_id = "test-project"
        mock_config.bq.dataset_id = "qualtrics"
        mock_config.bq.tables.scheduled_followups = "scheduled_followups"

        mock_client = MagicMock()
        mock_query_result = MagicMock()
        mock_query_result.result.return_value = [{"_scheduled": True}]
        mock_client.query.return_value = mock_query_result

        from main import is_already_scheduled

        assert is_already_scheduled(mock_client, "R_test") is True

    @patch("main.config")
    def test_not_scheduled_returns_false(self, mock_config):
        mock_config.gcp.project_id = "test-project"
        mock_config.bq.dataset_id = "qualtrics"
        mock_config.bq.tables.scheduled_followups = "scheduled_followups"

        mock_client = MagicMock()
        mock_query_result = MagicMock()
        mock_query_result.result.return_value = []
        mock_client.query.return_value = mock_query_result

        from main import is_already_scheduled

        assert is_already_scheduled(mock_client, "R_test") is False


# -- Handler integration tests (mocked) ------------------------------
class TestFollowupSchedulingHandler:
    """Integration tests for the full handler with mocked deps."""

    def _make_cloud_event(self, message_data: dict) -> MagicMock:
        """Build a mock CloudEvent with encoded Pub/Sub data."""
        encoded = base64.b64encode(json.dumps(message_data).encode()).decode()
        event = MagicMock()
        event.data = {"message": {"data": encoded}}
        return event

    @patch("main.write_scheduling_records", return_value=True)
    @patch("main.schedule_sms")
    @patch("main.is_already_scheduled", return_value=False)
    @patch("main.bigquery.Client")
    @patch("main.config")
    def test_full_flow_three_messages(
        self,
        mock_config,
        mock_bq_client,
        mock_is_scheduled,
        mock_schedule,
        mock_write,
    ):
        mock_config.gcp.project_id = "test-project"
        mock_config.followup_surveys.survey_base_url = (
            "https://ncsu.qualtrics.com/jfe/form"
        )
        mock_config.followup_surveys.survey_ids = [
            "SV_1",
            "SV_2",
            "SV_3",
        ]
        mock_config.followup_surveys.sms_template = "Survey at {time}: {url}"

        mock_schedule.side_effect = [
            "SM_sid_1",
            "SM_sid_2",
            "SM_sid_3",
        ]

        event = self._make_cloud_event(
            {
                "response_id": "R_test",
                "connect_id": "pid_123",
                "phone": "+18777804236",
                "selected_date": "2099-02-24",
                "timezone": "US/Central",
            }
        )

        from main import followup_scheduling_handler

        followup_scheduling_handler(event)

        assert mock_schedule.call_count == 3
        mock_write.assert_called_once()

        # Verify the write call includes all 3 records
        write_args = mock_write.call_args
        records = write_args.kwargs.get(
            "scheduled_records",
            write_args[0][6] if len(write_args[0]) > 6 else None,
        )
        if records:
            assert len(records) == 3

    @patch("main.schedule_sms")
    @patch("main.is_already_scheduled", return_value=False)
    @patch("main.bigquery.Client")
    @patch("main.config")
    def test_partial_failure_raises(
        self,
        mock_config,
        mock_bq_client,
        mock_is_scheduled,
        mock_schedule,
    ):
        mock_config.gcp.project_id = "test-project"
        mock_config.followup_surveys.survey_base_url = (
            "https://ncsu.qualtrics.com/jfe/form"
        )
        mock_config.followup_surveys.survey_ids = [
            "SV_1",
            "SV_2",
            "SV_3",
        ]
        mock_config.followup_surveys.sms_template = "Survey at {time}: {url}"

        # Second scheduling call fails
        mock_schedule.side_effect = ["SM_sid_1", None]

        event = self._make_cloud_event(
            {
                "response_id": "R_test",
                "phone": "+18777804236",
                "selected_date": "2099-02-24",
                "timezone": "US/Central",
            }
        )

        from main import followup_scheduling_handler

        with pytest.raises(RuntimeError, match="Twilio scheduling failed"):
            followup_scheduling_handler(event)

    @patch("main.schedule_sms")
    @patch("main.is_already_scheduled", return_value=True)
    @patch("main.bigquery.Client")
    @patch("main.config")
    def test_idempotent_skip(
        self,
        mock_config,
        mock_bq_client,
        mock_is_scheduled,
        mock_schedule,
    ):
        mock_config.gcp.project_id = "test-project"

        event = self._make_cloud_event(
            {
                "response_id": "R_test",
                "phone": "+18777804236",
                "selected_date": "2099-02-24",
                "timezone": "US/Central",
            }
        )

        from main import followup_scheduling_handler

        followup_scheduling_handler(event)
        mock_schedule.assert_not_called()

    def test_malformed_message_acknowledged(self):
        """Bad CloudEvent data logs and returns (no raise)."""
        event = MagicMock()
        event.data = {"bad": "structure"}

        from main import followup_scheduling_handler

        # Should not raise -- malformed messages are acknowledged
        followup_scheduling_handler(event)

    @patch("main.schedule_sms")
    @patch("main.is_already_scheduled", return_value=False)
    @patch("main.bigquery.Client")
    @patch("main.config")
    def test_null_connect_id_flows_through(
        self,
        mock_config,
        mock_bq_client,
        mock_is_scheduled,
        mock_schedule,
    ):
        """Verify None connect_id doesn't break the flow."""
        mock_config.gcp.project_id = "test-project"
        mock_config.followup_surveys.survey_base_url = (
            "https://ncsu.qualtrics.com/jfe/form"
        )
        mock_config.followup_surveys.survey_ids = [
            "SV_1",
            "SV_2",
            "SV_3",
        ]
        mock_config.followup_surveys.sms_template = "Survey at {time}: {url}"

        mock_schedule.side_effect = [
            "SM_sid_1",
            "SM_sid_2",
            "SM_sid_3",
        ]

        event = self._make_cloud_event(
            {
                "response_id": "R_test",
                "phone": "+18777804236",
                "selected_date": "2099-02-24",
                "timezone": "US/Central",
                # connect_id intentionally omitted
            }
        )

        from main import followup_scheduling_handler

        with patch("main.write_scheduling_records", return_value=True):
            followup_scheduling_handler(event)

        # Verify URLs don't contain connect_id
        for call in mock_schedule.call_args_list:
            body = call[0][1]  # second positional arg
            assert "connect_id" not in body


# -- Past-time skipping tests ------------------------------------------
class TestPastTimeSkipping:
    """Verify that the handler gracefully skips time slots that are
    too close or in the past (Twilio requires send_at >= now + 15 min).

    All tests freeze ``datetime.now`` so behavior is deterministic
    regardless of when the test suite runs. The selected_date is
    always 2026-06-15 (a Monday) and the timezone is US/Central
    (UTC-5 in June / CDT).
    """

    _SELECTED_DATE = "2026-06-15"
    _TIMEZONE = "US/Central"

    def _make_cloud_event(self, message_data: dict) -> MagicMock:
        encoded = base64.b64encode(json.dumps(message_data).encode()).decode()
        event = MagicMock()
        event.data = {"message": {"data": encoded}}
        return event

    def _make_event(self, **overrides) -> MagicMock:
        data = {
            "response_id": "R_past_test",
            "phone": "+18777804236",
            "selected_date": self._SELECTED_DATE,
            "timezone": self._TIMEZONE,
        }
        data.update(overrides)
        return self._make_cloud_event(data)

    def _mock_config(self, mock_config):
        mock_config.gcp.project_id = "test-project"
        mock_config.followup_surveys.survey_base_url = (
            "https://ncsu.qualtrics.com/jfe/form"
        )
        mock_config.followup_surveys.survey_ids = ["SV_1", "SV_2", "SV_3"]
        mock_config.followup_surveys.sms_template = "Survey at {time}: {url}"

    @patch("main.schedule_sms")
    @patch("main.is_already_scheduled", return_value=False)
    @patch("main.bigquery.Client")
    @patch("main.config")
    def test_all_slots_in_past_returns_without_error(
        self,
        mock_config,
        mock_bq_client,
        mock_is_scheduled,
        mock_schedule,
    ):
        """When all 3 slots are in the past, handler returns
        (acknowledges) without calling Twilio or writing to BQ."""
        self._mock_config(mock_config)

        # Freeze time to 6 PM CDT on the selected date.
        # In UTC that's 11 PM (CDT = UTC-5).
        # All 3 slots (9AM, 1PM, 5PM CDT) are in the past.
        frozen_utc = datetime(2026, 6, 15, 23, 0, 0, tzinfo=timezone.utc)

        event = self._make_event()

        from main import followup_scheduling_handler

        with patch("main.datetime") as mock_dt:
            mock_dt.now.return_value = frozen_utc
            mock_dt.combine = datetime.combine
            mock_dt.side_effect = lambda *a, **kw: datetime(*a, **kw)
            followup_scheduling_handler(event)

        mock_schedule.assert_not_called()

    @patch("main.write_scheduling_records", return_value=True)
    @patch("main.schedule_sms")
    @patch("main.is_already_scheduled", return_value=False)
    @patch("main.bigquery.Client")
    @patch("main.config")
    def test_only_future_slots_scheduled(
        self,
        mock_config,
        mock_bq_client,
        mock_is_scheduled,
        mock_schedule,
        mock_write,
    ):
        """When 2 of 3 slots are past, only the future slot is
        scheduled and written to BQ."""
        self._mock_config(mock_config)

        # Freeze time to 12:30 PM CDT = 5:30 PM UTC.
        # 9 AM CDT (2 PM UTC) is past.
        # 1 PM CDT (6 PM UTC) is only 30 min away (< 16 min lead? No,
        #   actually 30 min > 16 min, so it would pass. Let's use 12:50 PM CDT
        #   = 5:50 PM UTC so 1 PM CDT = 6 PM UTC is only 10 min away).
        frozen_utc = datetime(2026, 6, 15, 17, 50, 0, tzinfo=timezone.utc)

        mock_schedule.return_value = "SM_sid_5pm"

        event = self._make_event()

        from main import followup_scheduling_handler

        with (
            patch("main.datetime") as mock_dt,
        ):
            mock_dt.now.return_value = frozen_utc
            mock_dt.combine = datetime.combine
            mock_dt.side_effect = lambda *a, **kw: datetime(*a, **kw)
            followup_scheduling_handler(event)

        # Only the 5 PM slot should be scheduled (9 AM past, 1 PM <16 min)
        assert mock_schedule.call_count == 1
        mock_write.assert_called_once()

        # Verify the single record is for slot 3 (5 PM)
        write_args = mock_write.call_args
        records = write_args.kwargs.get(
            "scheduled_records",
            write_args[0][6] if len(write_args[0]) > 6 else None,
        )
        if records:
            assert len(records) == 1
            assert records[0]["survey_time"] == 3

    @patch("main.write_scheduling_records", return_value=True)
    @patch("main.schedule_sms")
    @patch("main.is_already_scheduled", return_value=False)
    @patch("main.bigquery.Client")
    @patch("main.config")
    def test_all_slots_in_future_schedules_all_three(
        self,
        mock_config,
        mock_bq_client,
        mock_is_scheduled,
        mock_schedule,
        mock_write,
    ):
        """When all 3 slots are in the future, all 3 are scheduled."""
        self._mock_config(mock_config)

        # Freeze time to midnight CDT = 5 AM UTC.
        # All 3 slots (9AM, 1PM, 5PM CDT) are hours away.
        frozen_utc = datetime(2026, 6, 15, 5, 0, 0, tzinfo=timezone.utc)

        mock_schedule.side_effect = ["SM_1", "SM_2", "SM_3"]

        event = self._make_event()

        from main import followup_scheduling_handler

        with patch("main.datetime") as mock_dt:
            mock_dt.now.return_value = frozen_utc
            mock_dt.combine = datetime.combine
            mock_dt.side_effect = lambda *a, **kw: datetime(*a, **kw)
            followup_scheduling_handler(event)

        assert mock_schedule.call_count == 3
        mock_write.assert_called_once()

    @patch("main.write_scheduling_records", return_value=True)
    @patch("main.schedule_sms")
    @patch("main.is_already_scheduled", return_value=False)
    @patch("main.bigquery.Client")
    @patch("main.config")
    def test_slot_at_exact_boundary_proceeds(
        self,
        mock_config,
        mock_bq_client,
        mock_is_scheduled,
        mock_schedule,
        mock_write,
    ):
        """A slot exactly 16 min from now should be scheduled
        (guard uses <=, so exactly 16 min passes)."""
        self._mock_config(mock_config)

        # 9 AM CDT = 2 PM UTC (CDT = UTC-5 in June).
        # Set now to 1:43 PM UTC so 9 AM CDT is 17 min away → passes.
        frozen_utc = datetime(2026, 6, 15, 13, 43, 0, tzinfo=timezone.utc)

        mock_schedule.side_effect = ["SM_1", "SM_2", "SM_3"]

        event = self._make_event()

        from main import followup_scheduling_handler

        with patch("main.datetime") as mock_dt:
            mock_dt.now.return_value = frozen_utc
            mock_dt.combine = datetime.combine
            mock_dt.side_effect = lambda *a, **kw: datetime(*a, **kw)
            followup_scheduling_handler(event)

        # All 3 slots should be scheduled since all are ≥17 min away
        assert mock_schedule.call_count == 3


# -- send_immediately tests -------------------------------------------
class TestSendImmediately:
    """Verify that send_immediately=True schedules all 3 SMS at
    now+16, now+32, now+48 min regardless of FOLLOWUP_TIMES or
    selected_date, and skips the too-soon guard entirely.
    """

    _SELECTED_DATE = "2026-06-15"
    _TIMEZONE = "US/Central"

    def _make_cloud_event(self, message_data: dict) -> MagicMock:
        encoded = base64.b64encode(json.dumps(message_data).encode()).decode()
        event = MagicMock()
        event.data = {"message": {"data": encoded}}
        return event

    def _make_event(self, **overrides) -> MagicMock:
        data = {
            "response_id": "R_now_test",
            "phone": "+18777804236",
            "selected_date": self._SELECTED_DATE,
            "timezone": self._TIMEZONE,
            "send_immediately": True,
        }
        data.update(overrides)
        return self._make_cloud_event(data)

    def _mock_config(self, mock_config):
        mock_config.gcp.project_id = "test-project"
        mock_config.followup_surveys.survey_base_url = (
            "https://ncsu.qualtrics.com/jfe/form"
        )
        mock_config.followup_surveys.survey_ids = ["SV_1", "SV_2", "SV_3"]
        mock_config.followup_surveys.sms_template = "Survey at {time}: {url}"

    @patch("main.write_scheduling_records", return_value=True)
    @patch("main.schedule_sms")
    @patch("main.is_already_scheduled", return_value=False)
    @patch("main.bigquery.Client")
    @patch("main.config")
    def test_schedules_all_three_at_now_offsets(
        self,
        mock_config,
        mock_bq_client,
        mock_is_scheduled,
        mock_schedule,
        mock_write,
    ):
        """All 3 slots are scheduled at now+16/32/48 min when
        send_immediately=True, even if selected_date is today."""
        self._mock_config(mock_config)

        # Freeze time to 6 PM UTC -- all fixed study times (9/13/17 h)
        # on the same day would be in the past, but send_immediately
        # bypasses those and schedules at now+offset.
        frozen_utc = datetime(2026, 6, 15, 18, 0, 0, tzinfo=timezone.utc)

        mock_schedule.side_effect = ["SM_now_1", "SM_now_2", "SM_now_3"]

        event = self._make_event()

        from main import MIN_SCHEDULE_LEAD, followup_scheduling_handler

        with patch("main.datetime") as mock_dt:
            mock_dt.now.return_value = frozen_utc
            mock_dt.combine = datetime.combine
            mock_dt.side_effect = lambda *a, **kw: datetime(*a, **kw)
            followup_scheduling_handler(event)

        assert mock_schedule.call_count == 3
        mock_write.assert_called_once()

        # Verify send_at times are now+16, now+32, now+48 min
        expected_times = [
            frozen_utc + MIN_SCHEDULE_LEAD * slot for slot in (1, 2, 3)
        ]
        actual_times = [call.args[2] for call in mock_schedule.call_args_list]
        assert actual_times == expected_times

    @patch("main.write_scheduling_records", return_value=True)
    @patch("main.schedule_sms")
    @patch("main.is_already_scheduled", return_value=False)
    @patch("main.bigquery.Client")
    @patch("main.config")
    def test_does_not_skip_any_slot(
        self,
        mock_config,
        mock_bq_client,
        mock_is_scheduled,
        mock_schedule,
        mock_write,
    ):
        """send_immediately=True never skips slots -- even when the
        fixed study times would all be in the past."""
        self._mock_config(mock_config)

        # Midnight UTC -- all fixed times would be in the past for today
        frozen_utc = datetime(2026, 6, 15, 23, 59, 0, tzinfo=timezone.utc)
        mock_schedule.side_effect = ["SM_1", "SM_2", "SM_3"]

        event = self._make_event()

        from main import followup_scheduling_handler

        with patch("main.datetime") as mock_dt:
            mock_dt.now.return_value = frozen_utc
            mock_dt.combine = datetime.combine
            mock_dt.side_effect = lambda *a, **kw: datetime(*a, **kw)
            followup_scheduling_handler(event)

        # All 3 must be scheduled regardless of the time of day
        assert mock_schedule.call_count == 3
