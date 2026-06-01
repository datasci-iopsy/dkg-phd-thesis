"""Add work classification and work shift questions to the intake survey draft.

Run once to create the questions and print their QIDs. Update
QID_PLACEHOLDER_WC and QID_PLACEHOLDER_WS in
gcp/cloud_run_functions/run_qualtrics_scheduling/models/qualtrics.py
with the values printed below.

Usage (from the worktree root):
    source ~/.bashrc && \\
    QUALTRICS_BASE_URL='https://yul1.qualtrics.com/API/v3' \\
    QUALTRICS_SURVEY_ID_1='SV_5nV942MJGubDmqq' \\
    QUALTRICS_SURVEY_ID_2='SV_eRKl4lgMZDAurT8' \\
    QUALTRICS_SURVEY_ID_3='SV_6J3svun1r97AAHc' \\
    uv run scripts/qualtrics/add_intake_questions.py

IMPORTANT: This creates DRAFT questions only. Do NOT publish the survey.
Update choice display text to human-readable labels before publishing.
work_shift choice labels are snake_case to match gcp_utils.yaml keys.
"""

import logging
import sys

from changes import INTAKE_ADDITIONS
from config import ScriptConfig
from updater import add_question

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

    logger.info("Adding %d questions to intake survey", len(INTAKE_ADDITIONS))

    qid_map: dict[str, str] = {}
    for addition in INTAKE_ADDITIONS:
        try:
            qid = add_question(
                addition.survey_id,
                addition.question_body,
                cfg.qualtrics_base_url,
                cfg.qualtrics_api_key,
            )
            qid_map[addition.field_name] = qid
            logger.info(
                "Created %s -> %s (%s)",
                addition.field_name,
                qid,
                addition.description,
            )
        except Exception as e:
            logger.error(
                "FAILED %s/%s: %s", addition.survey_id, addition.field_name, e
            )
            sys.exit(1)

    print("\n--- Update qualtrics.py QID_MAP with these values ---")
    for field_name, qid in qid_map.items():
        print(f'  "{field_name}": "{qid}",')
    print("-----------------------------------------------------\n")


if __name__ == "__main__":
    main()
