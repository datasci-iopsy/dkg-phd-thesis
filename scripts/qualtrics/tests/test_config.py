"""Tests for scripts/qualtrics/config.py.

Verifies that ScriptConfig loads from a .env file, raises on missing
required fields, and exposes survey IDs as an ordered list.
"""

from pathlib import Path

import pytest
from config import ScriptConfig


@pytest.fixture()
def env_file(tmp_path: Path) -> Path:
    f = tmp_path / ".env"
    f.write_text(
        "QUALTRICS_API_KEY=test-key\n"
        "QUALTRICS_BASE_URL=https://yul1.qualtrics.com/API/v3\n"
        "QUALTRICS_SURVEY_ID_1=SV_aaa\n"
        "QUALTRICS_SURVEY_ID_2=SV_bbb\n"
        "QUALTRICS_SURVEY_ID_3=SV_ccc\n"
    )
    return f


class TestScriptConfig:
    def test_loads_from_env_file(self, env_file: Path) -> None:
        cfg = ScriptConfig(_env_file=env_file)
        assert cfg.qualtrics_api_key == "test-key"

    def test_base_url(self, env_file: Path) -> None:
        cfg = ScriptConfig(_env_file=env_file)
        assert cfg.qualtrics_base_url == "https://yul1.qualtrics.com/API/v3"

    def test_survey_ids_list(self, env_file: Path) -> None:
        cfg = ScriptConfig(_env_file=env_file)
        assert cfg.followup_survey_ids == ["SV_aaa", "SV_bbb", "SV_ccc"]

    def test_survey_id_order(self, env_file: Path) -> None:
        cfg = ScriptConfig(_env_file=env_file)
        ids = cfg.followup_survey_ids
        assert ids[0] == "SV_aaa"
        assert ids[1] == "SV_bbb"
        assert ids[2] == "SV_ccc"

    def test_missing_api_key_raises(self, tmp_path: Path) -> None:
        f = tmp_path / ".env"
        f.write_text(
            "QUALTRICS_BASE_URL=https://yul1.qualtrics.com/API/v3\n"
            "QUALTRICS_SURVEY_ID_1=SV_aaa\n"
            "QUALTRICS_SURVEY_ID_2=SV_bbb\n"
            "QUALTRICS_SURVEY_ID_3=SV_ccc\n"
        )
        with pytest.raises(Exception):
            ScriptConfig(_env_file=f)

    def test_missing_survey_id_raises(self, tmp_path: Path) -> None:
        f = tmp_path / ".env"
        f.write_text(
            "QUALTRICS_API_KEY=test-key\n"
            "QUALTRICS_BASE_URL=https://yul1.qualtrics.com/API/v3\n"
            "QUALTRICS_SURVEY_ID_1=SV_aaa\n"
            "QUALTRICS_SURVEY_ID_2=SV_bbb\n"
        )
        with pytest.raises(Exception):
            ScriptConfig(_env_file=f)

    def test_env_var_overrides_file(
        self, env_file: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setenv("QUALTRICS_API_KEY", "override-key")
        cfg = ScriptConfig(_env_file=env_file)
        assert cfg.qualtrics_api_key == "override-key"
