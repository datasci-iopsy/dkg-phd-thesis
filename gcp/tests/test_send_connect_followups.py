"""Unit tests for scripts/send_connect_followups.py pure helpers."""

from __future__ import annotations

import sys
import os
from datetime import date, datetime, time, timezone
import zoneinfo

import pytest

sys.path.insert(
    0,
    os.path.join(os.path.dirname(__file__), "..", "..", "scripts"),
)

from send_connect_followups import (
    BASE_SURVEY_URL,
    DEFAULT_SHIFT,
    RESCHEDULE_IDS,
    RESCHEDULE_NOTE,
    SHIFT_TIMES,
    SURVEY_IDS,
    build_survey_url,
    compute_send_at_utc,
    format_time_label,
    get_shift_times,
    make_idempotency_token,
    parse_date,
    render_notification,
)


# ---- get_shift_times -------------------------------------------------


class TestGetShiftTimes:
    def test_first_shift_returns_three_times(self) -> None:
        result = get_shift_times("first_shift")
        assert len(result) == 3
        assert result == [
            time(9, 0),
            time(13, 0),
            time(17, 0),
        ]

    def test_early_shift(self) -> None:
        result = get_shift_times("early_shift")
        assert result == [time(6, 0), time(8, 45), time(11, 30)]

    def test_second_shift(self) -> None:
        result = get_shift_times("second_shift")
        assert result == [time(16, 0), time(19, 0), time(22, 0)]

    def test_third_shift(self) -> None:
        result = get_shift_times("third_shift")
        assert result == [time(1, 0), time(4, 0), time(7, 0)]

    def test_none_falls_back_to_default(self) -> None:
        assert get_shift_times(None) == get_shift_times(DEFAULT_SHIFT)

    def test_unknown_shift_falls_back_to_default(self) -> None:
        assert get_shift_times("unknown_shift") == get_shift_times(
            DEFAULT_SHIFT
        )

    def test_all_shifts_present(self) -> None:
        for shift in SHIFT_TIMES:
            times = get_shift_times(shift)
            assert len(times) == 3
            assert all(isinstance(t, time) for t in times)


# ---- format_time_label -----------------------------------------------


class TestFormatTimeLabel:
    @pytest.mark.parametrize(
        "t, expected",
        [
            (time(9, 0), "9:00 AM"),
            (time(13, 0), "1:00 PM"),
            (time(17, 0), "5:00 PM"),
            (time(0, 0), "12:00 AM"),
            (time(12, 0), "12:00 PM"),
            (time(6, 0), "6:00 AM"),
            (time(22, 0), "10:00 PM"),
            (time(8, 45), "8:45 AM"),
            (time(19, 0), "7:00 PM"),
            (time(1, 0), "1:00 AM"),
            (time(4, 0), "4:00 AM"),
        ],
    )
    def test_format(self, t: time, expected: str) -> None:
        assert format_time_label(t) == expected

    def test_pm_after_noon(self) -> None:
        assert "PM" in format_time_label(time(13, 0))

    def test_am_before_noon(self) -> None:
        assert "AM" in format_time_label(time(9, 0))


# ---- parse_date ------------------------------------------------------


class TestParseDate:
    def test_string_iso(self) -> None:
        assert parse_date("2026-06-05") == date(2026, 6, 5)

    def test_date_passthrough(self) -> None:
        d = date(2026, 6, 5)
        assert parse_date(d) is d

    def test_datetime_extracts_date(self) -> None:
        dt = datetime(2026, 6, 5, 9, 0, tzinfo=timezone.utc)
        assert parse_date(dt) == date(2026, 6, 5)


# ---- compute_send_at_utc ---------------------------------------------


class TestComputeSendAtUtc:
    def test_first_shift_eastern(self) -> None:
        result = compute_send_at_utc(
            date(2026, 6, 5),
            time(9, 0),
            "US/Eastern",
        )
        expected = datetime(2026, 6, 5, 13, 0, tzinfo=zoneinfo.ZoneInfo("UTC"))
        assert result == expected

    def test_first_shift_central(self) -> None:
        result = compute_send_at_utc(
            date(2026, 6, 5),
            time(9, 0),
            "US/Central",
        )
        expected = datetime(2026, 6, 5, 14, 0, tzinfo=zoneinfo.ZoneInfo("UTC"))
        assert result == expected

    def test_second_shift_crosses_midnight(self) -> None:
        result = compute_send_at_utc(
            date(2026, 6, 5),
            time(22, 0),
            "US/Eastern",
        )
        expected = datetime(2026, 6, 6, 2, 0, tzinfo=zoneinfo.ZoneInfo("UTC"))
        assert result == expected

    def test_result_is_utc(self) -> None:
        result = compute_send_at_utc(
            date(2026, 6, 5),
            time(9, 0),
            "US/Eastern",
        )
        assert result.tzinfo is not None
        assert result.utcoffset().total_seconds() == 0  # type: ignore[union-attr]


# ---- build_survey_url ------------------------------------------------


class TestBuildSurveyUrl:
    def test_url_contains_base(self) -> None:
        url = build_survey_url(
            SURVEY_IDS[0], "R_abc", "CONNECTID123", 1, "2026-06-05"
        )
        assert url.startswith(f"{BASE_SURVEY_URL}/{SURVEY_IDS[0]}")

    def test_url_contains_all_params(self) -> None:
        url = build_survey_url(
            SURVEY_IDS[1], "R_abc", "CONNECTID123", 2, "2026-06-05"
        )
        assert "response_id=R_abc" in url
        assert "survey_time=2" in url
        assert "selected_date=2026-06-05" in url
        assert "connect_id=CONNECTID123" in url

    def test_slot_survey_id_mapping(self) -> None:
        for slot_idx, survey_id in enumerate(SURVEY_IDS):
            url = build_survey_url(
                survey_id, "R_x", "CID", slot_idx + 1, "2026-06-05"
            )
            assert survey_id in url

    def test_different_slots_produce_different_urls(self) -> None:
        url1 = build_survey_url(SURVEY_IDS[0], "R_abc", "CID", 1, "2026-06-05")
        url2 = build_survey_url(SURVEY_IDS[1], "R_abc", "CID", 2, "2026-06-05")
        assert url1 != url2


# ---- make_idempotency_token ------------------------------------------


class TestMakeIdempotencyToken:
    def test_deterministic(self) -> None:
        t1 = make_idempotency_token("R_abc", 1, "2026-06-05")
        t2 = make_idempotency_token("R_abc", 1, "2026-06-05")
        assert t1 == t2

    def test_differs_by_slot(self) -> None:
        t1 = make_idempotency_token("R_abc", 1, "2026-06-05")
        t2 = make_idempotency_token("R_abc", 2, "2026-06-05")
        assert t1 != t2

    def test_differs_by_response_id(self) -> None:
        t1 = make_idempotency_token("R_abc", 1, "2026-06-05")
        t2 = make_idempotency_token("R_xyz", 1, "2026-06-05")
        assert t1 != t2

    def test_differs_by_date(self) -> None:
        t1 = make_idempotency_token("R_abc", 1, "2026-06-05")
        t2 = make_idempotency_token("R_abc", 1, "2026-06-12")
        assert t1 != t2

    def test_includes_all_components(self) -> None:
        token = make_idempotency_token("R_abc", 2, "2026-06-05")
        assert "R_abc" in token
        assert "2" in token
        assert "2026-06-05" in token


# ---- render_notification ---------------------------------------------


class TestRenderNotification:
    _base_row = {
        "response_id": "R_test",
        "connect_id": "a" * 32,
        "work_shift": "first_shift",
        "timezone": "US/Eastern",
    }

    def test_non_rescheduled_has_no_reschedule_note(self) -> None:
        body = render_notification(
            self._base_row,
            date(2026, 6, 5),
            is_rescheduled=False,
        )
        assert RESCHEDULE_NOTE not in body

    def test_rescheduled_includes_reschedule_note(self) -> None:
        body = render_notification(
            self._base_row,
            date(2026, 6, 5),
            is_rescheduled=True,
        )
        assert RESCHEDULE_NOTE in body

    def test_contains_date_long(self) -> None:
        body = render_notification(
            self._base_row,
            date(2026, 6, 5),
            is_rescheduled=False,
        )
        assert "Friday, June 05, 2026" in body

    def test_contains_timezone(self) -> None:
        body = render_notification(
            self._base_row,
            date(2026, 6, 5),
            is_rescheduled=False,
        )
        assert "US/Eastern" in body

    def test_contains_first_shift_window_labels(self) -> None:
        body = render_notification(
            self._base_row,
            date(2026, 6, 5),
            is_rescheduled=False,
        )
        assert "9:00 AM" in body
        assert "1:00 PM" in body
        assert "5:00 PM" in body

    def test_none_shift_falls_back_to_default(self) -> None:
        row = {**self._base_row, "work_shift": None}
        body_none = render_notification(row, date(2026, 6, 5), False)
        body_default = render_notification(
            {**self._base_row, "work_shift": DEFAULT_SHIFT},
            date(2026, 6, 5),
            False,
        )
        assert body_none == body_default

    def test_body_contains_no_unreplaced_placeholders(self) -> None:
        body = render_notification(
            self._base_row,
            date(2026, 6, 5),
            is_rescheduled=True,
        )
        assert "{" not in body
        assert "}" not in body

    def test_reschedule_ids_are_marked_as_rescheduled(self) -> None:
        for rid in RESCHEDULE_IDS:
            row = {**self._base_row, "response_id": rid}
            body = render_notification(
                row, date(2026, 6, 5), rid in RESCHEDULE_IDS
            )
            assert RESCHEDULE_NOTE in body
