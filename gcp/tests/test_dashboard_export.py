"""
Tests for the dashboard data export function.

Verifies:
  - _build_export_data assembles correct JSON shape from BQ rows
  - Response rates are calculated correctly per wave
  - Unknown wave numbers fall back to "Wave N" label
  - Overall follow-up rate aggregates all waves
  - Empty scheduled result returns zero counts, not a crash
  - _write_to_gcs uploads JSON with correct content-type and cache-control
  - dashboard_export_handler returns 200 on success with updated_at
  - dashboard_export_handler returns 500 when BQ query raises
  - dashboard_export_handler returns 500 when GCS write raises

All BQ and GCS calls are mocked -- no credentials or network access needed.

Usage from project root:
    uv run pytest gcp/tests/test_dashboard_export.py -v
"""

import importlib.util
import json
from pathlib import Path
from unittest.mock import MagicMock, patch

from flask import Flask

# -- Load run_dashboard_export main via importlib ----------------------
# Avoids any sys.path collision with other function main.py files.

_FN_DIR = (
    Path(__file__).parent.parent
    / "cloud_run_functions"
    / "run_dashboard_export"
)
_spec = importlib.util.spec_from_file_location(
    "run_dashboard_export_main", _FN_DIR / "main.py"
)
_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_module)

dashboard_export_handler = _module.dashboard_export_handler
_build_export_data = _module._build_export_data
_write_to_gcs = _module._write_to_gcs
_WAVE_LABELS = _module._WAVE_LABELS

_app = Flask(__name__)


# -- BQ row helpers -----------------------------------------------------


def _make_bq_row(wave: int, scheduled: int, completed: int, enrollment: int):
    """Build a mock BQ row dict matching the export query result shape."""
    row = MagicMock()
    row.__getitem__ = lambda self, key: {
        "wave": wave,
        "scheduled_count": scheduled,
        "completed_count": completed,
        "enrollment_total": enrollment,
    }[key]
    return row


# -- _build_export_data tests -------------------------------------------


class TestBuildExportData:
    """Verify the BQ query result is assembled into the correct JSON shape."""

    def _mock_rows(self, rows):
        mock_client = MagicMock()
        mock_client.query.return_value.result.return_value = iter(rows)
        return mock_client

    def test_enrollment_count_comes_from_first_row(self):
        rows = [
            _make_bq_row(wave=1, scheduled=10, completed=5, enrollment=42),
            _make_bq_row(wave=2, scheduled=10, completed=3, enrollment=42),
        ]
        with patch(
            "google.cloud.bigquery.Client", return_value=self._mock_rows(rows)
        ):
            with patch("google.cloud.storage.Client"):
                data = _build_export_data()
        assert data["enrollment"]["total"] == 42

    def test_response_rate_is_completed_over_scheduled(self):
        rows = [_make_bq_row(wave=1, scheduled=20, completed=5, enrollment=10)]
        with patch(
            "google.cloud.bigquery.Client", return_value=self._mock_rows(rows)
        ):
            with patch("google.cloud.storage.Client"):
                data = _build_export_data()
        wave = data["response_rates"][0]
        assert wave["rate"] == round(5 / 20, 4)
        assert wave["scheduled"] == 20
        assert wave["completed"] == 5

    def test_wave_labels_map_correctly(self):
        rows = [
            _make_bq_row(wave=1, scheduled=10, completed=1, enrollment=5),
            _make_bq_row(wave=2, scheduled=10, completed=1, enrollment=5),
            _make_bq_row(wave=3, scheduled=10, completed=1, enrollment=5),
        ]
        with patch(
            "google.cloud.bigquery.Client", return_value=self._mock_rows(rows)
        ):
            with patch("google.cloud.storage.Client"):
                data = _build_export_data()
        labels = [w["label"] for w in data["response_rates"]]
        assert labels == [
            "Morning (9 AM)",
            "Afternoon (1 PM)",
            "Evening (5 PM)",
        ]

    def test_unknown_wave_falls_back_to_wave_n(self):
        rows = [_make_bq_row(wave=9, scheduled=5, completed=1, enrollment=5)]
        with patch(
            "google.cloud.bigquery.Client", return_value=self._mock_rows(rows)
        ):
            with patch("google.cloud.storage.Client"):
                data = _build_export_data()
        assert data["response_rates"][0]["label"] == "Wave 9"

    def test_overall_followup_aggregates_all_waves(self):
        rows = [
            _make_bq_row(wave=1, scheduled=67, completed=10, enrollment=68),
            _make_bq_row(wave=2, scheduled=68, completed=15, enrollment=68),
            _make_bq_row(wave=3, scheduled=68, completed=8, enrollment=68),
        ]
        with patch(
            "google.cloud.bigquery.Client", return_value=self._mock_rows(rows)
        ):
            with patch("google.cloud.storage.Client"):
                data = _build_export_data()
        overall = data["overall_followup"]
        assert overall["scheduled"] == 203
        assert overall["completed"] == 33
        assert overall["rate"] == round(33 / 203, 4)

    def test_zero_scheduled_does_not_raise(self):
        rows = [_make_bq_row(wave=1, scheduled=0, completed=0, enrollment=0)]
        with patch(
            "google.cloud.bigquery.Client", return_value=self._mock_rows(rows)
        ):
            with patch("google.cloud.storage.Client"):
                data = _build_export_data()
        assert data["response_rates"][0]["rate"] == 0.0
        assert data["overall_followup"]["rate"] == 0.0

    def test_empty_rows_returns_zero_enrollment(self):
        with patch(
            "google.cloud.bigquery.Client", return_value=self._mock_rows([])
        ):
            with patch("google.cloud.storage.Client"):
                data = _build_export_data()
        assert data["enrollment"]["total"] == 0
        assert data["response_rates"] == []

    def test_updated_at_is_iso_format(self):
        rows = [_make_bq_row(wave=1, scheduled=10, completed=1, enrollment=5)]
        with patch(
            "google.cloud.bigquery.Client", return_value=self._mock_rows(rows)
        ):
            with patch("google.cloud.storage.Client"):
                data = _build_export_data()
        from datetime import datetime

        datetime.fromisoformat(data["updated_at"])


# -- _write_to_gcs tests ------------------------------------------------


class TestWriteToGcs:
    """Verify GCS upload uses correct content-type and cache-control."""

    def test_uploads_json_content_type(self):
        mock_blob = MagicMock()
        mock_bucket = MagicMock()
        mock_bucket.blob.return_value = mock_blob
        mock_client = MagicMock()
        mock_client.bucket.return_value = mock_bucket

        with patch("google.cloud.storage.Client", return_value=mock_client):
            _write_to_gcs({"enrollment": {"total": 5}, "response_rates": []})

        _, kwargs = mock_blob.upload_from_string.call_args
        assert kwargs.get("content_type") == "application/json"

    def test_upload_payload_is_valid_json(self):
        mock_blob = MagicMock()
        mock_bucket = MagicMock()
        mock_bucket.blob.return_value = mock_blob
        mock_client = MagicMock()
        mock_client.bucket.return_value = mock_bucket

        payload = {"enrollment": {"total": 10}, "response_rates": []}
        with patch("google.cloud.storage.Client", return_value=mock_client):
            _write_to_gcs(payload)

        args, _ = mock_blob.upload_from_string.call_args
        parsed = json.loads(args[0])
        assert parsed["enrollment"]["total"] == 10

    def test_sets_no_cache_header(self):
        mock_blob = MagicMock()
        mock_bucket = MagicMock()
        mock_bucket.blob.return_value = mock_blob
        mock_client = MagicMock()
        mock_client.bucket.return_value = mock_bucket

        with patch("google.cloud.storage.Client", return_value=mock_client):
            _write_to_gcs({"enrollment": {"total": 0}, "response_rates": []})

        assert mock_blob.cache_control == "no-cache, max-age=0"


# -- HTTP handler tests -------------------------------------------------


class TestDashboardExportHandler:
    """Verify the HTTP handler returns correct status codes."""

    def _mock_bq_rows(self, rows):
        mock_client = MagicMock()
        mock_client.query.return_value.result.return_value = iter(rows)
        return mock_client

    def test_returns_200_on_success(self):
        rows = [_make_bq_row(wave=1, scheduled=10, completed=1, enrollment=5)]
        mock_bq = self._mock_bq_rows(rows)
        mock_blob = MagicMock()
        mock_bucket = MagicMock()
        mock_bucket.blob.return_value = mock_blob
        mock_gcs = MagicMock()
        mock_gcs.bucket.return_value = mock_bucket

        with patch("google.cloud.bigquery.Client", return_value=mock_bq):
            with patch("google.cloud.storage.Client", return_value=mock_gcs):
                with _app.test_request_context("/"):
                    from flask import request as flask_request

                    response, status = dashboard_export_handler(flask_request)

        assert status == 200
        body = json.loads(response.data)
        assert body["status"] == "ok"
        assert "updated_at" in body

    def test_returns_500_when_bq_raises(self):
        mock_bq = MagicMock()
        mock_bq.query.side_effect = Exception("BQ unavailable")

        with patch("google.cloud.bigquery.Client", return_value=mock_bq):
            with _app.test_request_context("/"):
                from flask import request as flask_request

                response, status = dashboard_export_handler(flask_request)

        assert status == 500
        body = json.loads(response.data)
        assert "error" in body

    def test_returns_500_when_gcs_raises(self):
        rows = [_make_bq_row(wave=1, scheduled=10, completed=1, enrollment=5)]
        mock_bq = self._mock_bq_rows(rows)
        mock_gcs = MagicMock()
        mock_gcs.bucket.side_effect = Exception("GCS unavailable")

        with patch("google.cloud.bigquery.Client", return_value=mock_bq):
            with patch("google.cloud.storage.Client", return_value=mock_gcs):
                with _app.test_request_context("/"):
                    from flask import request as flask_request

                    response, status = dashboard_export_handler(flask_request)

        assert status == 500
