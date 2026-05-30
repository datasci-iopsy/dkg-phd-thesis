"""
Tests for the dashboard data export function.

Verifies:
  - _build_export_data assembles correct JSON shape from BQ rows
  - Response rates are calculated correctly per wave
  - Unknown wave numbers fall back to "Wave N" label
  - Overall follow-up rate aggregates all waves
  - Empty scheduled result returns zero counts, not a crash
  - _deploy_to_netlify creates a deploy manifest with all site files
  - _deploy_to_netlify uploads only the files Netlify requires
  - _deploy_to_netlify raises KeyError if Netlify requests an unknown file
  - dashboard_export_handler returns 200 on success with updated_at
  - dashboard_export_handler returns 500 when BQ query raises
  - dashboard_export_handler returns 500 when Netlify deploy raises

All BQ and HTTP calls are mocked -- no credentials or network access needed.

Usage from project root:
    uv run pytest gcp/tests/test_dashboard_export.py -v
"""

import hashlib
import importlib.util
import json
import os
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest
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
_deploy_to_netlify = _module._deploy_to_netlify

_app = Flask(__name__)

_NETLIFY_API = "https://api.netlify.com/api/v1"
_SITE_ID = "de1a02c0-802a-4da9-97a0-00131aff6b02"
_TOKEN = "test-netlify-token"


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


def _make_netlify_mock(required: list[str] | None = None):
    """Return a requests.post mock that simulates a Netlify deploy response."""
    mock_post_resp = MagicMock()
    mock_post_resp.raise_for_status = MagicMock()
    mock_post_resp.json.return_value = {
        "id": "deploy-abc123",
        "required": required or [],
    }
    mock_put_resp = MagicMock()
    mock_put_resp.raise_for_status = MagicMock()

    mock_requests = MagicMock()
    mock_requests.post.return_value = mock_post_resp
    mock_requests.put.return_value = mock_put_resp
    return mock_requests


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
            data = _build_export_data()
        assert data["enrollment"]["total"] == 42

    def test_response_rate_is_completed_over_scheduled(self):
        rows = [_make_bq_row(wave=1, scheduled=20, completed=5, enrollment=10)]
        with patch(
            "google.cloud.bigquery.Client", return_value=self._mock_rows(rows)
        ):
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
            data = _build_export_data()
        assert data["response_rates"][0]["rate"] == 0.0
        assert data["overall_followup"]["rate"] == 0.0

    def test_empty_rows_returns_zero_enrollment(self):
        with patch(
            "google.cloud.bigquery.Client", return_value=self._mock_rows([])
        ):
            data = _build_export_data()
        assert data["enrollment"]["total"] == 0
        assert data["response_rates"] == []

    def test_updated_at_is_iso_format(self):
        rows = [_make_bq_row(wave=1, scheduled=10, completed=1, enrollment=5)]
        with patch(
            "google.cloud.bigquery.Client", return_value=self._mock_rows(rows)
        ):
            data = _build_export_data()
        from datetime import datetime

        datetime.fromisoformat(data["updated_at"])


# -- _deploy_to_netlify tests -------------------------------------------


class TestDeployToNetlify:
    """Verify the Netlify deploy API is called correctly."""

    _payload = {"enrollment": {"total": 5}, "response_rates": []}

    def test_creates_deploy_with_data_json_in_manifest(self):
        mock_requests = _make_netlify_mock(required=[])
        with patch.dict(os.environ, {"NETLIFY_API_KEY": _TOKEN}):
            with patch("requests.post", mock_requests.post):
                with patch("requests.put", mock_requests.put):
                    _deploy_to_netlify(self._payload)

        _, kwargs = mock_requests.post.call_args
        manifest = kwargs["json"]["files"]
        assert "/data.json" in manifest

    def test_manifest_includes_static_site_files(self):
        mock_requests = _make_netlify_mock(required=[])
        with patch.dict(os.environ, {"NETLIFY_API_KEY": _TOKEN}):
            with patch("requests.post", mock_requests.post):
                with patch("requests.put", mock_requests.put):
                    _deploy_to_netlify(self._payload)

        _, kwargs = mock_requests.post.call_args
        manifest = kwargs["json"]["files"]
        assert "/index.html" in manifest
        assert "/netlify.toml" in manifest

    def test_uploads_only_required_files(self):
        # Netlify required array contains SHA1 hashes, not paths
        data_sha = hashlib.sha1(
            json.dumps(self._payload, indent=2).encode()
        ).hexdigest()
        mock_requests = _make_netlify_mock(required=[data_sha])
        with patch.dict(os.environ, {"NETLIFY_API_KEY": _TOKEN}):
            with patch("requests.post", mock_requests.post):
                with patch("requests.put", mock_requests.put):
                    _deploy_to_netlify(self._payload)

        assert mock_requests.put.call_count == 1
        put_url = mock_requests.put.call_args[0][0]
        assert "/data.json" in put_url

    def test_skips_upload_when_nothing_required(self):
        mock_requests = _make_netlify_mock(required=[])
        with patch.dict(os.environ, {"NETLIFY_API_KEY": _TOKEN}):
            with patch("requests.post", mock_requests.post):
                with patch("requests.put", mock_requests.put):
                    _deploy_to_netlify(self._payload)

        mock_requests.put.assert_not_called()

    def test_raises_on_unknown_required_file(self):
        # A hash that won't match any file in the manifest
        mock_requests = _make_netlify_mock(required=["a" * 40])
        with patch.dict(os.environ, {"NETLIFY_API_KEY": _TOKEN}):
            with patch("requests.post", mock_requests.post):
                with patch("requests.put", mock_requests.put):
                    with pytest.raises(KeyError):
                        _deploy_to_netlify(self._payload)

    def test_data_json_upload_is_valid_json(self):
        payload = {"enrollment": {"total": 42}, "response_rates": []}
        data_sha = hashlib.sha1(
            json.dumps(payload, indent=2).encode()
        ).hexdigest()
        mock_requests = _make_netlify_mock(required=[data_sha])
        with patch.dict(os.environ, {"NETLIFY_API_KEY": _TOKEN}):
            with patch("requests.post", mock_requests.post):
                with patch("requests.put", mock_requests.put):
                    _deploy_to_netlify(payload)

        uploaded_bytes = mock_requests.put.call_args[1]["data"]
        parsed = json.loads(uploaded_bytes)
        assert parsed["enrollment"]["total"] == 42


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
        mock_requests = _make_netlify_mock(required=[])

        with patch("google.cloud.bigquery.Client", return_value=mock_bq):
            with patch.dict(os.environ, {"NETLIFY_API_KEY": _TOKEN}):
                with patch("requests.post", mock_requests.post):
                    with patch("requests.put", mock_requests.put):
                        with _app.test_request_context("/"):
                            from flask import request as flask_request

                            response, status = dashboard_export_handler(
                                flask_request
                            )

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

    def test_returns_500_when_netlify_raises(self):
        rows = [_make_bq_row(wave=1, scheduled=10, completed=1, enrollment=5)]
        mock_bq = self._mock_bq_rows(rows)
        mock_post = MagicMock(side_effect=Exception("Netlify unavailable"))

        with patch("google.cloud.bigquery.Client", return_value=mock_bq):
            with patch.dict(os.environ, {"NETLIFY_API_KEY": _TOKEN}):
                with patch("requests.post", mock_post):
                    with _app.test_request_context("/"):
                        from flask import request as flask_request

                        response, status = dashboard_export_handler(
                            flask_request
                        )

        assert status == 500
