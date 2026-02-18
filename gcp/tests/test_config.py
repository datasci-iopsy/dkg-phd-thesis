"""
Tests for config loading and Pydantic validation.

Usage from project root:
    poetry run pytest gcp/tests/test_config.py
Usage from gcp/tests/:
    poetry run pytest test_config.py
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
    assert config.bq.tables.intake_raw == "intake_responses"
    assert config.bq.tables.intake_clean == "intake_clean"
    assert config.bq.tables.followup_raw == "followup_responses"
    assert config.bq.tables.followup_clean == "followup_clean"
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
