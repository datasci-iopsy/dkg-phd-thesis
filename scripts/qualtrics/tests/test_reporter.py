"""Tests for scripts/qualtrics/reporter.py.

Verifies that format_survey_report produces human-readable output
containing all required fields without making any I/O calls.
"""

import pytest
from client import Question, SurveyDefinition
from reporter import SEPARATOR, format_survey_report


@pytest.fixture()
def survey() -> SurveyDefinition:
    return SurveyDefinition(
        survey_id="SV_test123",
        survey_name="Followup Survey 1",
        questions=[
            Question(
                question_id="QID1",
                question_text="How are you feeling?",
                question_type="MC",
                question_name="feeling",
            ),
            Question(
                question_id="QID2",
                question_text="Rate your energy.",
                question_type="Slider",
                question_name=None,
            ),
        ],
    )


@pytest.fixture()
def report(survey: SurveyDefinition) -> str:
    return format_survey_report(survey)


class TestFormatSurveyReport:
    def test_returns_string(self, report: str) -> None:
        assert isinstance(report, str)

    def test_contains_survey_name(self, report: str) -> None:
        assert "Followup Survey 1" in report

    def test_contains_survey_id(self, report: str) -> None:
        assert "SV_test123" in report

    def test_contains_question_count(self, report: str) -> None:
        assert "2" in report

    def test_contains_separator(self, report: str) -> None:
        assert SEPARATOR in report

    def test_contains_question_ids(self, report: str) -> None:
        assert "QID1" in report
        assert "QID2" in report

    def test_contains_question_text(self, report: str) -> None:
        assert "How are you feeling?" in report
        assert "Rate your energy." in report

    def test_contains_question_type(self, report: str) -> None:
        assert "MC" in report
        assert "Slider" in report

    def test_contains_question_name(self, report: str) -> None:
        assert "feeling" in report

    def test_multiline_question_text_collapsed(self) -> None:
        survey = SurveyDefinition(
            survey_id="SV_x",
            survey_name="Test",
            questions=[
                Question(
                    question_id="QID1",
                    question_text="Line one\nLine two",
                    question_type="TE",
                )
            ],
        )
        report = format_survey_report(survey)
        assert "\n\nLine two" not in report
        assert "Line one" in report

    def test_empty_survey_has_zero_questions(self) -> None:
        survey = SurveyDefinition(
            survey_id="SV_empty",
            survey_name="Empty",
            questions=[],
        )
        report = format_survey_report(survey)
        assert "Questions: 0" in report
