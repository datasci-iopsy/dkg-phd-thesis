"""Tests for gcp/deploy/trigger_unscheduled_participants.py::build_message."""

from __future__ import annotations

import importlib.util
import json
from datetime import date
from pathlib import Path

import pytest

# Load the deploy script as a module without executing main().
_script_path = (
    Path(__file__).resolve().parent.parent
    / "deploy"
    / "trigger_unscheduled_participants.py"
)
_spec = importlib.util.spec_from_file_location(
    "trigger_unscheduled_participants", _script_path
)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
build_message = _mod.build_message


def _base_row(**overrides: object) -> dict:
    row = {
        "response_id": "R_testABC",
        "connect_id": "0019A30A1F2C41C685A9CE494181EED2",
        "phone": "gAAAAABfake_encrypted_phone_value",
        "selected_date": date(2026, 6, 5),
        "timezone": "US/Eastern",
        "work_shift": "first_shift",
    }
    row.update(overrides)
    return row


class TestBuildMessageWorkShift:
    def test_work_shift_included_when_present(self) -> None:
        msg = build_message(_base_row(work_shift="second_shift"))
        assert msg["work_shift"] == "second_shift"

    def test_work_shift_none_when_absent(self) -> None:
        row = _base_row()
        del row["work_shift"]
        msg = build_message(row)
        assert msg["work_shift"] is None

    def test_work_shift_none_when_null(self) -> None:
        msg = build_message(_base_row(work_shift=None))
        assert msg["work_shift"] is None

    @pytest.mark.parametrize(
        "shift",
        ["early_shift", "first_shift", "second_shift", "third_shift"],
    )
    def test_all_valid_shifts_pass_through(self, shift: str) -> None:
        msg = build_message(_base_row(work_shift=shift))
        assert msg["work_shift"] == shift


class TestBuildMessageDateSerialization:
    def test_date_object_serialized_to_iso_string(self) -> None:
        msg = build_message(_base_row(selected_date=date(2026, 6, 5)))
        assert msg["selected_date"] == "2026-06-05"

    def test_string_date_passes_through_unchanged(self) -> None:
        msg = build_message(_base_row(selected_date="2026-06-08"))
        assert msg["selected_date"] == "2026-06-08"

    def test_date_object_round_trips_through_json(self) -> None:
        msg = build_message(_base_row(selected_date=date(2026, 6, 12)))
        serialized = json.dumps(msg)
        parsed = json.loads(serialized)
        assert parsed["selected_date"] == "2026-06-12"


class TestBuildMessageOtherFields:
    def test_send_immediately_always_false(self) -> None:
        msg = build_message(_base_row())
        assert msg["send_immediately"] is False

    def test_connect_id_passes_through(self) -> None:
        cid = "ABCD1234" * 4
        msg = build_message(_base_row(connect_id=cid))
        assert msg["connect_id"] == cid

    def test_connect_id_none_passes_through(self) -> None:
        msg = build_message(_base_row(connect_id=None))
        assert msg["connect_id"] is None

    def test_phone_passes_through_unmodified(self) -> None:
        phone = "gAAAAABfake_encrypted_value_xyz"
        msg = build_message(_base_row(phone=phone))
        assert msg["phone"] == phone

    def test_required_fields_all_present(self) -> None:
        msg = build_message(_base_row())
        for field in (
            "response_id",
            "connect_id",
            "phone",
            "selected_date",
            "timezone",
            "work_shift",
            "send_immediately",
        ):
            assert field in msg, f"Missing field: {field}"
