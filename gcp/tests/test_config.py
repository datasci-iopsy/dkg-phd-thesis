"""
Tests for config loading and Pydantic validation.

Usage from project root:
    uv run pytest gcp/tests/test_config.py
Usage from gcp/tests/:
    uv run pytest test_config.py
"""

from pathlib import Path

import pytest
from shared.utils.config_loader import load_config

# Path to the qualtrics scheduling function's configs
CONFIGS_DIR = (
    Path(__file__).resolve().parent.parent
    / "cloud_run_functions"
    / "run_qualtrics_scheduling"
    / "configs"
)


def test_load_config_returns_valid_appconfig():
    """Happy path: all YAML fields present and valid."""
    config = load_config(CONFIGS_DIR)

    assert config.gcp.project_id == "dkg-phd-thesis"
    assert config.gcp.location == "US"
    assert config.gcp.region == "us-east4"
    assert config.bq.dataset_id == "qualtrics"
    assert config.bq.tables.intake_raw == "stg_intake_responses"
    assert config.bq.tables.intake_clean == "int_intake_responses_scored"
    assert config.bq.tables.followup_raw == "stg_followup_responses"
    assert config.bq.tables.followup_clean == "int_followup_responses_scored"
    assert "qualtrics.com/API/v3" in config.qualtrics.base_url
    assert config.qualtrics.survey_base_url.startswith("https://")


def test_config_dot_notation_access():
    """Verify dot-notation works through all nested levels."""
    config = load_config(CONFIGS_DIR)

    assert isinstance(config.gcp.project_id, str)
    assert isinstance(config.gcp.location, str)
    assert isinstance(config.gcp.region, str)
    assert isinstance(config.bq.tables.intake_raw, str)
    assert isinstance(config.bq.tables.followup_raw, str)


def test_secret_manager_is_optional():
    """Config loads successfully without a secret_manager block."""
    config = load_config(CONFIGS_DIR)
    assert config.secret_manager is None


def test_missing_directory_raises():
    """Non-existent config directory should raise FileNotFoundError."""
    with pytest.raises(FileNotFoundError, match="Config directory not found"):
        load_config("/nonexistent/path")


def test_empty_directory_raises(tmp_path):
    """Directory with no YAML files should raise FileNotFoundError."""
    with pytest.raises(FileNotFoundError, match="No YAML config files"):
        load_config(tmp_path)


def test_missing_required_field_raises(tmp_path):
    """Missing a required field should raise ValidationError."""
    incomplete = tmp_path / "partial.yaml"
    incomplete.write_text(
        "gcp:\n  project_id: test\n  location: US\n  region: us-east4\n"
    )

    with pytest.raises(Exception, match="bq"):
        load_config(tmp_path)


# -- ShiftTimesConfig model tests (Slice B) --------------------------
_FN3_CONFIGS_DIR = (
    Path(__file__).resolve().parent.parent
    / "cloud_run_functions"
    / "run_followup_scheduling"
    / "configs"
)


class TestShiftTimesConfig:
    """Verify ShiftTimesConfig validates and loads from fn3 YAML."""

    def test_valid_shift_times_config(self):
        """A fully populated ShiftTimesConfig constructs successfully."""
        from shared.utils.config_models import ShiftTimesConfig

        cfg = ShiftTimesConfig(
            default_shift="first_shift",
            shifts={"first_shift": ["09:00", "13:00", "17:00"]},
        )
        assert cfg.default_shift == "first_shift"
        assert cfg.shifts["first_shift"] == ["09:00", "13:00", "17:00"]

    def test_shift_times_config_missing_default_shift_raises(self):
        """Missing default_shift is rejected by Pydantic."""
        from pydantic import ValidationError

        from shared.utils.config_models import ShiftTimesConfig

        with pytest.raises(ValidationError):
            ShiftTimesConfig(
                shifts={"first_shift": ["09:00", "13:00", "17:00"]}
            )

    def test_shift_times_config_missing_shifts_raises(self):
        """Missing shifts dict is rejected by Pydantic."""
        from pydantic import ValidationError

        from shared.utils.config_models import ShiftTimesConfig

        with pytest.raises(ValidationError):
            ShiftTimesConfig(default_shift="first_shift")

    def test_fn3_config_loads_shift_times(self):
        """fn3 config YAML includes all 4 canonical bins with no placeholders."""
        config = load_config(_FN3_CONFIGS_DIR)
        assert config.shift_times is not None
        assert config.shift_times.default_shift == "first_shift"

        shifts = config.shift_times.shifts
        assert set(shifts.keys()) == {
            "early_shift",
            "first_shift",
            "second_shift",
            "third_shift",
        }
        assert shifts["early_shift"] == ["06:00", "08:45", "11:30"]
        assert shifts["first_shift"] == ["09:00", "13:00", "17:00"]
        assert shifts["second_shift"] == ["16:00", "19:00", "22:00"]
        assert shifts["third_shift"] == ["01:00", "04:00", "07:00"]

        # Guard against re-introduction of placeholder bins
        for key in shifts:
            assert not key.startswith("part_time"), f"stale bin: {key}"
        for times in shifts.values():
            for t in times:
                assert t != "PLACEHOLDER", f"PLACEHOLDER found in {times}"


# -- ConnectConfig model tests (connect-live-pipeline) ----------------


class TestConnectConfig:
    """ConnectConfig validates fields and integrates into AppConfig."""

    def test_connect_config_constructs_with_defaults(self):
        """ConnectConfig accepts required fields and applies defaults."""
        from shared.utils.config_models import ConnectConfig

        cfg = ConnectConfig(
            base_url="https://connect-api.cloudresearch.com",
            cloudresearch_project_id="ee2a7726-0745-4952-8646-00ba758d57a9",
            survey_base_url="https://ncsu.qualtrics.com/jfe/form",
            survey_ids=["SV_a", "SV_b", "SV_c"],
            notification_template="Hello {date}",
            survey_message_template="Survey: {time} {url}",
        )
        assert cfg.min_lead_seconds == 1800

    def test_connect_config_rejects_wrong_survey_id_count(self):
        """Fewer than 3 survey_ids raises ValidationError."""
        from pydantic import ValidationError

        from shared.utils.config_models import ConnectConfig

        with pytest.raises(ValidationError):
            ConnectConfig(
                base_url="https://connect-api.cloudresearch.com",
                cloudresearch_project_id="ee2a7726",
                survey_base_url="https://ncsu.qualtrics.com/jfe/form",
                survey_ids=["SV_a", "SV_b"],
                notification_template="Hello {date}",
                survey_message_template="Survey: {time} {url}",
            )

    def test_app_config_connect_is_optional(self):
        """AppConfig loads without a connect block; field defaults to None."""
        config = load_config(CONFIGS_DIR)
        assert config.connect is None

    def test_pubsub_connect_topic_id_defaults_to_none(self):
        """PubSubConfig.connect_topic_id is optional and defaults to None."""
        config = load_config(CONFIGS_DIR)
        assert config.pubsub is not None
        assert config.pubsub.connect_topic_id is None


# -- ConnectSchedulingMessage model tests -----------------------------


class TestConnectSchedulingMessage:
    """ConnectSchedulingMessage carries Connect participant data without phone."""

    def test_message_constructs_with_required_fields(self):
        """Happy-path: all required fields set, optional fields at defaults."""
        from shared.utils.pubsub_utils import ConnectSchedulingMessage

        msg = ConnectSchedulingMessage(
            response_id="R_abc123",
            connect_id="aabbccdd11223344aabbccdd11223344",
            selected_date="2026-06-10",
            timezone="US/Eastern",
        )
        assert msg.response_id == "R_abc123"
        assert msg.connect_id == "aabbccdd11223344aabbccdd11223344"
        assert msg.send_immediately is False
        assert msg.work_shift is None

    def test_message_has_no_phone_field(self):
        """ConnectSchedulingMessage must not expose a phone field."""
        from shared.utils.pubsub_utils import ConnectSchedulingMessage

        msg = ConnectSchedulingMessage(
            response_id="R_abc123",
            connect_id="aabbccdd11223344aabbccdd11223344",
            selected_date="2026-06-10",
            timezone="US/Eastern",
        )
        assert not hasattr(msg, "phone")

    def test_message_send_immediately_and_work_shift_settable(self):
        """send_immediately and work_shift are settable."""
        from shared.utils.pubsub_utils import ConnectSchedulingMessage

        msg = ConnectSchedulingMessage(
            response_id="R_abc123",
            connect_id="aabbccdd11223344aabbccdd11223344",
            selected_date="2026-06-10",
            timezone="US/Eastern",
            send_immediately=True,
            work_shift="second_shift",
        )
        assert msg.send_immediately is True
        assert msg.work_shift == "second_shift"

    def test_publish_connect_scheduling_uses_connect_topic_id(self):
        """publish_connect_scheduling publishes to connect_topic_id."""
        from unittest.mock import MagicMock, patch

        from shared.utils.pubsub_utils import (
            ConnectSchedulingMessage,
            publish_connect_scheduling,
        )

        msg = ConnectSchedulingMessage(
            response_id="R_abc123",
            connect_id="aabbccdd11223344aabbccdd11223344",
            selected_date="2026-06-10",
            timezone="US/Eastern",
        )

        mock_config = MagicMock()
        mock_config.gcp.project_id = "dkg-phd-thesis"
        mock_config.pubsub.connect_topic_id = "dkg-connect-scheduling"

        mock_future = MagicMock()
        mock_future.result.return_value = "msg-id-123"

        with patch(
            "shared.utils.pubsub_utils.get_publisher_client"
        ) as mock_client_fn:
            mock_client = MagicMock()
            mock_client.topic_path.return_value = (
                "projects/dkg-phd-thesis/topics/dkg-connect-scheduling"
            )
            mock_client.publish.return_value = mock_future
            mock_client_fn.return_value = mock_client

            result = publish_connect_scheduling(msg, mock_config)

        assert result == "msg-id-123"
        mock_client.publish.assert_called_once()

    def test_publish_connect_scheduling_returns_none_if_no_pubsub(self):
        """Returns None when config.pubsub is None."""
        from unittest.mock import MagicMock

        from shared.utils.pubsub_utils import (
            ConnectSchedulingMessage,
            publish_connect_scheduling,
        )

        msg = ConnectSchedulingMessage(
            response_id="R_abc123",
            connect_id="aabbccdd11223344aabbccdd11223344",
            selected_date="2026-06-10",
            timezone="US/Eastern",
        )
        mock_config = MagicMock()
        mock_config.pubsub = None
        result = publish_connect_scheduling(msg, mock_config)
        assert result is None

    def test_publish_connect_scheduling_returns_none_if_no_connect_topic(self):
        """Returns None when connect_topic_id is not configured."""
        from unittest.mock import MagicMock

        from shared.utils.pubsub_utils import (
            ConnectSchedulingMessage,
            publish_connect_scheduling,
        )

        msg = ConnectSchedulingMessage(
            response_id="R_abc123",
            connect_id="aabbccdd11223344aabbccdd11223344",
            selected_date="2026-06-10",
            timezone="US/Eastern",
        )
        mock_config = MagicMock()
        mock_config.pubsub.connect_topic_id = None
        result = publish_connect_scheduling(msg, mock_config)
        assert result is None
