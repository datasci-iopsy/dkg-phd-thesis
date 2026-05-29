"""Apply and verify targeted wording changes across the three followup surveys.

Usage:
    uv run scripts/qualtrics/update_surveys.py

Reads credentials from environment / .env (same as inspect_surveys.py).
Applies all changes in the manifest, then re-fetches each question to
confirm 1:1 match before reporting success.
"""

import logging
import sys

from changes import CHANGES
from config import ScriptConfig
from updater import update_question_text, verify_question_text

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

    logger.info("Applying %d question changes across 3 surveys", len(CHANGES))

    failures: list[str] = []
    for change in CHANGES:
        try:
            update_question_text(
                change, cfg.qualtrics_base_url, cfg.qualtrics_api_key
            )
        except Exception as e:
            msg = f"UPDATE FAILED {change.survey_id}/{change.question_id}: {e}"
            logger.error(msg)
            failures.append(msg)

    if failures:
        logger.error(
            "%d update(s) failed; aborting verification", len(failures)
        )
        sys.exit(1)

    logger.info("All updates sent. Verifying 1:1 match...")

    mismatches: list[str] = []
    for change in CHANGES:
        try:
            ok, current = verify_question_text(
                change, cfg.qualtrics_base_url, cfg.qualtrics_api_key
            )
            if not ok:
                msg = (
                    f"MISMATCH {change.survey_id}/{change.question_id} ({change.description})\n"
                    f"  expected: {change.replace_text!r}\n"
                    f"  actual:   {current!r}"
                )
                logger.error(msg)
                mismatches.append(msg)
            else:
                logger.info(
                    "OK %s/%s (%s)",
                    change.survey_id,
                    change.question_id,
                    change.description,
                )
        except Exception as e:
            msg = f"VERIFY ERROR {change.survey_id}/{change.question_id}: {e}"
            logger.error(msg)
            mismatches.append(msg)

    if mismatches:
        logger.error(
            "%d verification failure(s). Review output above.", len(mismatches)
        )
        sys.exit(1)

    logger.info(
        "All %d changes verified. Surveys updated successfully.", len(CHANGES)
    )


if __name__ == "__main__":
    main()
