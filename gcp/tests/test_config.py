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
