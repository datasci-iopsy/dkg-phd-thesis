"""Unit and handler tests for run_connect_scheduling.

Tests the Connect API scheduling function: helpers, BQ guards, and
the full handler matrix (mocked BQ + requests + CloudEvent).

All GCP and Connect API calls are mocked -- no credentials needed.

Usage from project root:
    uv run pytest gcp/tests/test_connect_scheduling.py -v
"""

from __future__ import annotations

import base64
import importlib.util
import json
import zoneinfo
from datetime import UTC, date, datetime, time
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

# ---------------------------------------------------------------------------
# Load run_connect_scheduling/main.py via importlib (avoids sys.path shadowing
# by run_followup_scheduling/main.py, which conftest.py inserts at index 0).
# Same technique used by test_followup_response.py for fn4.
# ---------------------------------------------------------------------------

_FN_CONNECT_DIR = (
    Path(__file__).parent.parent
    / "cloud_run_functions"
    / "run_connect_scheduling"
)
_fn_connect_spec = importlib.util.spec_from_file_location(
    "run_connect_scheduling_main", _FN_CONNECT_DIR / "main.py"
)
_fn_connect_module = importlib.util.module_from_spec(_fn_connect_spec)
_fn_connect_spec.loader.exec_module(_fn_connect_module)

# Expose symbols under short names for use in tests
get_followup_times = _fn_connect_module.get_followup_times
format_time_label = _fn_connect_module.format_time_label
parse_date = _fn_connect_module.parse_date
compute_send_at_utc = _fn_connect_module.compute_send_at_utc
build_survey_url = _fn_connect_module.build_survey_url
make_idempotency_token = _fn_connect_module.make_idempotency_token
connect_scheduling_handler = _fn_connect_module.connect_scheduling_handler


# ---------------------------------------------------------------------------
# Helpers for building test CloudEvents (mirrors fn3 test pattern)
# ---------------------------------------------------------------------------


def _make_cloud_event(payload: dict) -> object:
    """Wrap a dict payload as a minimal CloudEvent-like object."""
    encoded = base64.b64encode(json.dumps(payload).encode()).decode()

    class _FakeCloudEvent:
        data = {"message": {"data": encoded}}

    return _FakeCloudEvent()


# ---------------------------------------------------------------------------
# Task 2: Helper parity tests
# ---------------------------------------------------------------------------


class TestGetFollowupTimesConnect:
    """get_followup_times reads shift_times from config."""

    def test_first_shift_returns_three_times(self):
        mock_shift = MagicMock()
        mock_shift.default_shift = "first_shift"
        mock_shift.shifts = {"first_shift": ["09:00", "13:00", "17:00"]}

        with patch.object(_fn_connect_module, "config") as mock_cfg:
            mock_cfg.shift_times = mock_shift
            result = get_followup_times("first_shift")

        assert result == [time(9, 0), time(13, 0), time(17, 0)]

    def test_none_work_shift_uses_default(self):
        mock_shift = MagicMock()
        mock_shift.default_shift = "first_shift"
        mock_shift.shifts = {"first_shift": ["09:00", "13:00", "17:00"]}

        with patch.object(_fn_connect_module, "config") as mock_cfg:
            mock_cfg.shift_times = mock_shift
            result = get_followup_times(None)

        assert result == [time(9, 0), time(13, 0), time(17, 0)]

    def test_missing_shift_times_config_raises(self):
        with patch.object(_fn_connect_module, "config") as mock_cfg:
            mock_cfg.shift_times = None
            with pytest.raises(RuntimeError, match="shift_times missing"):
                get_followup_times("first_shift")


class TestFormatTimeLabelConnect:
    """format_time_label formats time objects as 12-hour strings."""

    @pytest.mark.parametrize(
        ("t", "expected"),
        [
            (time(9, 0), "9:00 AM"),
            (time(13, 0), "1:00 PM"),
            (time(17, 0), "5:00 PM"),
            (time(0, 0), "12:00 AM"),
            (time(12, 0), "12:00 PM"),
            (time(6, 0), "6:00 AM"),
            (time(22, 0), "10:00 PM"),
            (time(8, 45), "8:45 AM"),
            (time(1, 0), "1:00 AM"),
        ],
    )
    def test_format(self, t: time, expected: str) -> None:
        assert format_time_label(t) == expected


class TestParseDateConnect:
    """parse_date coerces BQ string/date/datetime to date."""

    def test_string_iso(self):
        assert parse_date("2026-06-10") == date(2026, 6, 10)

    def test_date_passthrough(self):
        d = date(2026, 6, 10)
        assert parse_date(d) is d

    def test_datetime_extracts_date(self):
        dt = datetime(2026, 6, 10, 9, 0, tzinfo=UTC)
        assert parse_date(dt) == date(2026, 6, 10)


class TestComputeSendAtUtcConnect:
    """compute_send_at_utc converts local survey times to UTC."""

    def test_eastern_to_utc(self):
        result = compute_send_at_utc(
            date(2026, 6, 10), time(9, 0), "US/Eastern"
        )
        assert result.hour == 13
        assert result.tzinfo is not None

    def test_central_to_utc(self):
        result = compute_send_at_utc(
            date(2026, 6, 10), time(9, 0), "US/Central"
        )
        assert result.hour == 14

    def test_unknown_timezone_raises(self):
        with pytest.raises(zoneinfo.ZoneInfoNotFoundError):
            compute_send_at_utc(date(2026, 6, 10), time(9, 0), "Bogus/Zone")


class TestBuildSurveyUrlConnect:
    """build_survey_url produces URLs with correct parameters."""

    def test_url_contains_required_params(self):
        with patch.object(_fn_connect_module, "config") as mock_cfg:
            mock_cfg.connect.survey_base_url = (
                "https://ncsu.qualtrics.com/jfe/form"
            )
            url = build_survey_url(
                survey_id="SV_abc",
                response_id="R_test123",
                connect_id="aabbccdd11223344aabbccdd11223344",
                survey_time=1,
                selected_date_str="2026-06-10",
            )

        assert "response_id=R_test123" in url
        assert "survey_time=1" in url
        assert "SV_abc" in url
        assert "connect_id=" in url

    def test_url_uses_config_base(self):
        with patch.object(_fn_connect_module, "config") as mock_cfg:
            mock_cfg.connect.survey_base_url = (
                "https://ncsu.qualtrics.com/jfe/form"
            )
            url = build_survey_url("SV_abc", "R_1", "cc" * 16, 2, "2026-06-10")

        assert url.startswith("https://ncsu.qualtrics.com/jfe/form/SV_abc")


class TestMakeIdempotencyToken:
    """make_idempotency_token produces deterministic tokens."""

    def test_format(self):
        token = make_idempotency_token("R_abc123", 2, "2026-06-10")
        assert token == "R_abc123-2-2026-06-10"

    def test_deterministic(self):
        t1 = make_idempotency_token("R_xyz", 1, "2026-06-10")
        t2 = make_idempotency_token("R_xyz", 1, "2026-06-10")
        assert t1 == t2

    def test_slots_differ(self):
        t1 = make_idempotency_token("R_xyz", 1, "2026-06-10")
        t2 = make_idempotency_token("R_xyz", 2, "2026-06-10")
        assert t1 != t2


# ---------------------------------------------------------------------------
# Task 3: Handler integration tests (mocked BQ + Connect API + CloudEvent)
# ---------------------------------------------------------------------------


class TestConnectSchedulingHandler:
    """Full handler matrix -- all BQ and Connect API calls mocked.

    Each test asserts on calls made to patched module-level functions;
    no credentials or network access needed.
    """

    _CONNECT_ID = "aabbccdd11223344aabbccdd11223344"
    _RESPONSE_ID = "R_test_connect_001"
    _FUTURE_DATE = "2099-12-31"
    _PAST_DATE = "2020-01-01"

    def _make_message(self, **overrides) -> dict:
        base = {
            "response_id": self._RESPONSE_ID,
            "connect_id": self._CONNECT_ID,
            "selected_date": self._FUTURE_DATE,
            "timezone": "US/Eastern",
            "send_immediately": False,
            "work_shift": "first_shift",
        }
        base.update(overrides)
        return base

    def _setup_config(self, mock_cfg: object) -> None:
        mock_cfg.gcp.project_id = "test-project"
        mock_cfg.bq.dataset_id = "qualtrics"
        mock_cfg.bq.tables.intake_raw = "stg_intake_responses"
        mock_cfg.bq.tables.scheduled_followups = "scheduled_followups"
        mock_cfg.connect = MagicMock()
        mock_cfg.connect.min_lead_seconds = 1800
        mock_cfg.connect.survey_ids = ["SV_1", "SV_2", "SV_3"]
        mock_cfg.connect.cloudresearch_project_id = "proj-123"
        mock_cfg.connect.survey_base_url = "https://ncsu.qualtrics.com/jfe/form"
        mock_cfg.connect.survey_message_template = "Survey at {time}: {url}"
        mock_cfg.connect.notification_template = (
            "Surveys on {selected_date_long} at {window_1}, {window_2},"
            " {window_3} ({timezone_label})."
        )
        mock_cfg.shift_times = MagicMock()
        mock_cfg.shift_times.default_shift = "first_shift"
        mock_cfg.shift_times.shifts = {
            "first_shift": ["09:00", "13:00", "17:00"]
        }

    # -- Full flow -------------------------------------------------------

    def test_full_flow_three_slots(self):
        """Normal path: 3 bulk sends + 3 BQ inserts + 1 notification + flip."""
        event = _make_cloud_event(self._make_message())

        with (
            patch.object(_fn_connect_module, "config") as mock_cfg,
            patch.object(_fn_connect_module, "bigquery"),
            patch.object(
                _fn_connect_module, "is_already_processed", return_value=False
            ),
            patch.object(
                _fn_connect_module, "slot_already_scheduled", return_value=False
            ),
            patch.object(
                _fn_connect_module,
                "insert_scheduling_record",
                return_value=True,
            ) as mock_insert,
            patch.object(
                _fn_connect_module, "update_processed_flag", return_value=True
            ) as mock_flip,
            patch.object(_fn_connect_module, "_connect_request") as mock_api,
            patch.object(
                _fn_connect_module,
                "render_notification",
                return_value="Hello!",
            ),
        ):
            self._setup_config(mock_cfg)
            connect_scheduling_handler(event)

        bulk_calls = [
            c
            for c in mock_api.call_args_list
            if c.args[1] == "/api/v1/conversations/send-bulk-message"
        ]
        notif_calls = [
            c
            for c in mock_api.call_args_list
            if c.args[1] == "/api/v1/conversations/send-message"
        ]
        assert len(bulk_calls) == 3
        assert len(notif_calls) == 1
        assert mock_insert.call_count == 3
        mock_flip.assert_called_once()

    # -- Idempotency guards ---------------------------------------------

    def test_already_processed_acks_immediately(self):
        """_processed=TRUE: ack immediately, zero API or BQ write calls."""
        event = _make_cloud_event(self._make_message())

        with (
            patch.object(_fn_connect_module, "config") as mock_cfg,
            patch.object(_fn_connect_module, "bigquery"),
            patch.object(
                _fn_connect_module, "is_already_processed", return_value=True
            ),
            patch.object(_fn_connect_module, "_connect_request") as mock_api,
            patch.object(
                _fn_connect_module, "insert_scheduling_record"
            ) as mock_insert,
            patch.object(
                _fn_connect_module, "update_processed_flag"
            ) as mock_flip,
        ):
            self._setup_config(mock_cfg)
            connect_scheduling_handler(event)

        mock_api.assert_not_called()
        mock_insert.assert_not_called()
        mock_flip.assert_not_called()

    def test_slot_precheck_skips_send_but_counts(self):
        """Slot 1 already in BQ: skip its API call but count it; notify + flip."""
        event = _make_cloud_event(self._make_message())

        with (
            patch.object(_fn_connect_module, "config") as mock_cfg,
            patch.object(_fn_connect_module, "bigquery"),
            patch.object(
                _fn_connect_module, "is_already_processed", return_value=False
            ),
            patch.object(
                _fn_connect_module,
                "slot_already_scheduled",
                side_effect=[True, False, False],
            ),
            patch.object(
                _fn_connect_module,
                "insert_scheduling_record",
                return_value=True,
            ) as mock_insert,
            patch.object(
                _fn_connect_module, "update_processed_flag", return_value=True
            ) as mock_flip,
            patch.object(_fn_connect_module, "_connect_request") as mock_api,
            patch.object(
                _fn_connect_module,
                "render_notification",
                return_value="Hello!",
            ),
        ):
            self._setup_config(mock_cfg)
            connect_scheduling_handler(event)

        # Slot 1 pre-check hit: 2 bulk sends (slots 2+3) + 1 notification
        bulk_calls = [
            c
            for c in mock_api.call_args_list
            if c.args[1] == "/api/v1/conversations/send-bulk-message"
        ]
        assert len(bulk_calls) == 2
        assert mock_insert.call_count == 2
        mock_flip.assert_called_once()

    # -- Lead-window skip -----------------------------------------------

    def test_all_slots_past_lead_no_notification(self):
        """Past date: all slots within lead window; no sends, no flip."""
        event = _make_cloud_event(
            self._make_message(selected_date=self._PAST_DATE)
        )

        with (
            patch.object(_fn_connect_module, "config") as mock_cfg,
            patch.object(_fn_connect_module, "bigquery"),
            patch.object(
                _fn_connect_module, "is_already_processed", return_value=False
            ),
            patch.object(
                _fn_connect_module, "slot_already_scheduled", return_value=False
            ),
            patch.object(_fn_connect_module, "_connect_request") as mock_api,
            patch.object(
                _fn_connect_module, "insert_scheduling_record"
            ) as mock_insert,
            patch.object(
                _fn_connect_module, "update_processed_flag"
            ) as mock_flip,
        ):
            self._setup_config(mock_cfg)
            connect_scheduling_handler(event)

        mock_api.assert_not_called()
        mock_insert.assert_not_called()
        mock_flip.assert_not_called()

    # -- Error paths ----------------------------------------------------

    def test_slot_send_raises_propagates(self):
        """Bulk-message send failure raises; Pub/Sub retries the message."""
        event = _make_cloud_event(self._make_message())

        with (
            patch.object(_fn_connect_module, "config") as mock_cfg,
            patch.object(_fn_connect_module, "bigquery"),
            patch.object(
                _fn_connect_module, "is_already_processed", return_value=False
            ),
            patch.object(
                _fn_connect_module, "slot_already_scheduled", return_value=False
            ),
            patch.object(
                _fn_connect_module,
                "_connect_request",
                side_effect=Exception("API down"),
            ),
        ):
            self._setup_config(mock_cfg)
            with pytest.raises(Exception, match="API down"):
                connect_scheduling_handler(event)

    def test_bad_timezone_acks_no_raise(self):
        """Unrecognized timezone: log + ack, no exception."""
        event = _make_cloud_event(self._make_message(timezone="Bogus/Zone"))

        with (
            patch.object(_fn_connect_module, "config") as mock_cfg,
            patch.object(_fn_connect_module, "bigquery"),
            patch.object(_fn_connect_module, "_connect_request") as mock_api,
        ):
            self._setup_config(mock_cfg)
            connect_scheduling_handler(event)

        mock_api.assert_not_called()

    def test_bad_date_acks_no_raise(self):
        """Unparseable date string: log + ack, no exception."""
        event = _make_cloud_event(
            self._make_message(selected_date="not-a-date")
        )

        with (
            patch.object(_fn_connect_module, "config") as mock_cfg,
            patch.object(_fn_connect_module, "bigquery"),
            patch.object(_fn_connect_module, "_connect_request") as mock_api,
        ):
            self._setup_config(mock_cfg)
            connect_scheduling_handler(event)

        mock_api.assert_not_called()

    def test_malformed_message_acks_no_raise(self):
        """Missing required Pydantic fields: log + ack, no exception."""
        event = _make_cloud_event({"response_id": "R_only"})

        with (
            patch.object(_fn_connect_module, "config") as mock_cfg,
            patch.object(_fn_connect_module, "bigquery"),
            patch.object(_fn_connect_module, "_connect_request") as mock_api,
        ):
            self._setup_config(mock_cfg)
            connect_scheduling_handler(event)

        mock_api.assert_not_called()

    # -- send_immediately path ------------------------------------------

    def test_send_immediately_sends_all_three(self):
        """`send_immediately=True` bypasses lead check even for past dates."""
        event = _make_cloud_event(
            self._make_message(
                send_immediately=True, selected_date=self._PAST_DATE
            )
        )

        with (
            patch.object(_fn_connect_module, "config") as mock_cfg,
            patch.object(_fn_connect_module, "bigquery"),
            patch.object(
                _fn_connect_module, "is_already_processed", return_value=False
            ),
            patch.object(
                _fn_connect_module, "slot_already_scheduled", return_value=False
            ),
            patch.object(
                _fn_connect_module,
                "insert_scheduling_record",
                return_value=True,
            ),
            patch.object(
                _fn_connect_module, "update_processed_flag", return_value=True
            ),
            patch.object(_fn_connect_module, "_connect_request") as mock_api,
            patch.object(
                _fn_connect_module,
                "render_notification",
                return_value="Hello!",
            ),
        ):
            self._setup_config(mock_cfg)
            connect_scheduling_handler(event)

        bulk_calls = [
            c
            for c in mock_api.call_args_list
            if c.args[1] == "/api/v1/conversations/send-bulk-message"
        ]
        assert len(bulk_calls) == 3

    # -- Notification non-fatal ----------------------------------------

    def test_notification_failure_is_nonfatal(self):
        """Notification send failure: _processed flip still runs, no raise."""
        event = _make_cloud_event(self._make_message())

        def _api_side_effect(*args, **kwargs):
            if args[1] == "/api/v1/conversations/send-message":
                raise Exception("notification failed")

        with (
            patch.object(_fn_connect_module, "config") as mock_cfg,
            patch.object(_fn_connect_module, "bigquery"),
            patch.object(
                _fn_connect_module, "is_already_processed", return_value=False
            ),
            patch.object(
                _fn_connect_module, "slot_already_scheduled", return_value=False
            ),
            patch.object(
                _fn_connect_module,
                "insert_scheduling_record",
                return_value=True,
            ),
            patch.object(
                _fn_connect_module, "update_processed_flag", return_value=True
            ) as mock_flip,
            patch.object(
                _fn_connect_module,
                "_connect_request",
                side_effect=_api_side_effect,
            ),
            patch.object(
                _fn_connect_module,
                "render_notification",
                return_value="Hello!",
            ),
        ):
            self._setup_config(mock_cfg)
            connect_scheduling_handler(event)

        mock_flip.assert_called_once()
