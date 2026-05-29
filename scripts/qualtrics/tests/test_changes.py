"""Tests for scripts/qualtrics/changes.py.

Verifies the change manifest is structurally sound before any API calls.
"""

import pytest
from changes import CHANGES, P1, P2, P3, QuestionChange

KNOWN_SURVEY_IDS = {P1, P2, P3}


class TestQuestionChange:
    def test_frozen_dataclass(self) -> None:
        change = QuestionChange(
            survey_id=P1, question_id="QID1", replace_text="New."
        )
        with pytest.raises((AttributeError, TypeError)):
            change.replace_text = "Other"  # type: ignore[misc]

    def test_find_text_defaults_to_none(self) -> None:
        change = QuestionChange(
            survey_id=P1, question_id="QID1", replace_text="New."
        )
        assert change.find_text is None

    def test_description_defaults_to_empty(self) -> None:
        change = QuestionChange(
            survey_id=P1, question_id="QID1", replace_text="New."
        )
        assert change.description == ""


class TestChangesManifest:
    def test_changes_is_nonempty_list(self) -> None:
        assert isinstance(CHANGES, list)
        assert len(CHANGES) > 0

    def test_all_items_are_question_change(self) -> None:
        assert all(isinstance(c, QuestionChange) for c in CHANGES)

    def test_all_survey_ids_are_known(self) -> None:
        unknown = {c.survey_id for c in CHANGES} - KNOWN_SURVEY_IDS
        assert unknown == set(), f"Unknown survey IDs: {unknown}"

    def test_all_question_ids_nonempty(self) -> None:
        empty = [c for c in CHANGES if not c.question_id]
        assert empty == [], f"Empty question IDs: {empty}"

    def test_all_replace_texts_nonempty(self) -> None:
        empty = [c for c in CHANGES if not c.replace_text]
        assert empty == [], f"Empty replace_text: {empty}"

    def test_find_texts_nonempty_when_set(self) -> None:
        bad = [
            c for c in CHANGES if c.find_text is not None and not c.find_text
        ]
        assert bad == [], f"Empty find_text: {bad}"

    def test_no_duplicate_survey_question_pairs(self) -> None:
        pairs = [(c.survey_id, c.question_id) for c in CHANGES]
        assert len(pairs) == len(set(pairs)), (
            "Duplicate (survey_id, question_id) pairs found"
        )

    def test_all_three_surveys_represented(self) -> None:
        ids_in_manifest = {c.survey_id for c in CHANGES}
        assert ids_in_manifest == KNOWN_SURVEY_IDS

    def test_each_survey_has_at_least_fifteen_changes(self) -> None:
        for survey_id in KNOWN_SURVEY_IDS:
            count = sum(1 for c in CHANGES if c.survey_id == survey_id)
            assert count >= 15, f"{survey_id} has only {count} changes"
