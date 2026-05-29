"""Inspect followup survey question wording via the Qualtrics API.

Fetches the survey definitions for the three followup surveys and prints
a human-readable report of all question IDs, names, types, and text.

Usage:
    uv run scripts/qualtrics/inspect_surveys.py

Required environment variables:
    QUALTRICS_API_KEY       Qualtrics API token
    QUALTRICS_BASE_URL      API base URL (e.g. https://yul1.qualtrics.com/API/v3)
    QUALTRICS_SURVEY_ID_1   Followup survey ID for timepoint 1
    QUALTRICS_SURVEY_ID_2   Followup survey ID for timepoint 2
    QUALTRICS_SURVEY_ID_3   Followup survey ID for timepoint 3
"""

import logging
import os
import sys

from client import fetch_survey_definition
from reporter import format_survey_report

logging.basicConfig(
    level=logging.INFO,
    format="%(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)

FOLLOWUP_SURVEY_ENV_VARS = [
    "QUALTRICS_SURVEY_ID_1",
    "QUALTRICS_SURVEY_ID_2",
    "QUALTRICS_SURVEY_ID_3",
]


def load_config() -> tuple[str, str, list[str]]:
    """Load and validate required environment variables.

    Returns:
        Tuple of (api_key, base_url, survey_ids).

    Raises:
        SystemExit: If any required variable is missing.
    """
    missing = [
        v
        for v in [
            "QUALTRICS_API_KEY",
            "QUALTRICS_BASE_URL",
            *FOLLOWUP_SURVEY_ENV_VARS,
        ]
        if not os.environ.get(v)
    ]
    if missing:
        logger.error("Missing required environment variables: %s", missing)
        sys.exit(1)

    api_key = os.environ["QUALTRICS_API_KEY"]
    base_url = os.environ["QUALTRICS_BASE_URL"]
    survey_ids = [os.environ[v] for v in FOLLOWUP_SURVEY_ENV_VARS]
    return api_key, base_url, survey_ids


def main() -> None:
    api_key, base_url, survey_ids = load_config()

    for survey_id in survey_ids:
        try:
            definition = fetch_survey_definition(survey_id, base_url, api_key)
            print(format_survey_report(definition))
        except Exception as e:
            logger.error("Failed to fetch survey %s: %s", survey_id, e)
            sys.exit(1)


if __name__ == "__main__":
    main()
