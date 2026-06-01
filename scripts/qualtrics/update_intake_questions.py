"""Update the work_shift question (QID100) choices to the finalized 4-bin set.

Run this once after the intake survey draft already contains QID100
(created by add_intake_questions.py in Slice C). The script PUTs the
finalized Choices / ChoiceOrder / QuestionText onto the existing question.

IMPORTANT: This modifies the DRAFT survey only. Do NOT publish the survey.
Update choice display text to human-readable labels before publishing;
the snake_case Display values are keys that must match gcp_utils.yaml.

Usage (from the worktree root):
    source ~/.bashrc && \\
    QUALTRICS_BASE_URL='https://yul1.qualtrics.com/API/v3' \\
    QUALTRICS_SURVEY_ID_1='SV_5nV942MJGubDmqq' \\
    QUALTRICS_SURVEY_ID_2='SV_eRKl4lgMZDAurT8' \\
    QUALTRICS_SURVEY_ID_3='SV_6J3svun1r97AAHc' \\
    uv run scripts/qualtrics/update_intake_questions.py
"""

import logging
import sys

from changes import INTAKE, INTAKE_ADDITIONS, WORK_SHIFT_QID
from config import ScriptConfig
from updater import fetch_question, put_question

logging.basicConfig(
    level=logging.INFO,
    format="%(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)

_EXPECTED_SHIFT_KEYS = {
    "early_shift",
    "first_shift",
    "second_shift",
    "third_shift",
}


def _work_shift_body() -> dict:
    """Return the desired question body for work_shift from the manifest."""
    for addition in INTAKE_ADDITIONS:
        if addition.field_name == "work_shift":
            return addition.question_body
    raise RuntimeError("work_shift not found in INTAKE_ADDITIONS")


def main() -> None:
    try:
        cfg = ScriptConfig()
    except Exception:
        logger.exception("Configuration error")
        sys.exit(1)

    desired = _work_shift_body()

    logger.info("Fetching current state of %s/%s", INTAKE, WORK_SHIFT_QID)
    try:
        current = fetch_question(
            INTAKE,
            WORK_SHIFT_QID,
            cfg.qualtrics_base_url,
            cfg.qualtrics_api_key,
        )
    except Exception as e:
        logger.error("Failed to fetch %s/%s: %s", INTAKE, WORK_SHIFT_QID, e)
        sys.exit(1)

    # Merge desired fields onto the fetched body so we preserve any
    # Qualtrics-managed fields (DataExportTag, QuestionID, etc.).
    updated = {
        **current,
        "QuestionText": desired["QuestionText"],
        "Choices": desired["Choices"],
        "ChoiceOrder": desired["ChoiceOrder"],
    }

    logger.info("Putting 4-bin choices onto %s/%s", INTAKE, WORK_SHIFT_QID)
    try:
        put_question(
            INTAKE,
            WORK_SHIFT_QID,
            updated,
            cfg.qualtrics_base_url,
            cfg.qualtrics_api_key,
        )
    except Exception as e:
        logger.error("PUT failed for %s/%s: %s", INTAKE, WORK_SHIFT_QID, e)
        sys.exit(1)

    logger.info("PUT succeeded. Verifying...")

    try:
        result = fetch_question(
            INTAKE,
            WORK_SHIFT_QID,
            cfg.qualtrics_base_url,
            cfg.qualtrics_api_key,
        )
    except Exception as e:
        logger.error("Verification fetch failed: %s", e)
        sys.exit(1)

    actual_keys = {c["Display"] for c in result.get("Choices", {}).values()}
    if actual_keys != _EXPECTED_SHIFT_KEYS:
        logger.error(
            "Choice mismatch after PUT.\n  expected: %s\n  actual:   %s",
            sorted(_EXPECTED_SHIFT_KEYS),
            sorted(actual_keys),
        )
        sys.exit(1)

    logger.info(
        "Verified: %s/%s now has 4 bins: %s",
        INTAKE,
        WORK_SHIFT_QID,
        sorted(actual_keys),
    )
    logger.info("Done. Remember to update display labels before publishing.")


if __name__ == "__main__":
    main()
