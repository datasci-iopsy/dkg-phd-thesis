"""Configuration for Qualtrics inspection scripts.

Loads from environment variables and .env file via pydantic-settings.
Environment variables take precedence over .env file values.
"""

from pathlib import Path

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

_DEFAULT_ENV_FILE = Path(__file__).resolve().parent.parent.parent / ".env"


class ScriptConfig(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=_DEFAULT_ENV_FILE,
        env_file_encoding="utf-8",
        extra="ignore",
    )

    qualtrics_api_key: str
    qualtrics_base_url: str
    qualtrics_survey_id_1: str
    qualtrics_survey_id_2: str
    qualtrics_survey_id_3: str

    @model_validator(mode="after")
    def check_no_empty_values(self) -> "ScriptConfig":
        for field in (
            "qualtrics_api_key",
            "qualtrics_base_url",
            "qualtrics_survey_id_1",
            "qualtrics_survey_id_2",
            "qualtrics_survey_id_3",
        ):
            if not getattr(self, field):
                raise ValueError(f"{field} must not be empty")
        return self

    @property
    def followup_survey_ids(self) -> list[str]:
        return [
            self.qualtrics_survey_id_1,
            self.qualtrics_survey_id_2,
            self.qualtrics_survey_id_3,
        ]
