"""Inspect followup survey question wording via the Qualtrics API.

Fetches the survey definitions for the three followup surveys and prints
a human-readable report of all question IDs, names, types, and text.

Usage:
    uv run scripts/qualtrics/inspect_surveys.py

Reads credentials and survey IDs from environment variables or .env:
    QUALTRICS_API_KEY       Qualtrics API token
    QUALTRICS_BASE_URL      API base URL (e.g. https://yul1.qualtrics.com/API/v3)
    QUALTRICS_SURVEY_ID_1   Followup survey ID for timepoint 1
    QUALTRICS_SURVEY_ID_2   Followup survey ID for timepoint 2
    QUALTRICS_SURVEY_ID_3   Followup survey ID for timepoint 3
"""

import logging
import sys

from client import fetch_survey_definition
from config import ScriptConfig
from reporter import format_survey_report

logging.basicConfig(
    level=logging.INFO,
    format="%(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


def main() -> None:
    try:
        cfg = ScriptConfig()
    except Exception as e:
        logger.error("Configuration error: %s", e)
        sys.exit(1)

    for survey_id in cfg.followup_survey_ids:
        try:
            definition = fetch_survey_definition(
                survey_id, cfg.qualtrics_base_url, cfg.qualtrics_api_key
            )
            print(format_survey_report(definition))
        except Exception as e:
            logger.error("Failed to fetch survey %s: %s", survey_id, e)
            sys.exit(1)


if __name__ == "__main__":
    main()
