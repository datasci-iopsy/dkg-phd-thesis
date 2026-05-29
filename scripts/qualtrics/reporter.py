"""Survey inspection output formatter.

Formats SurveyDefinition objects for human review. No I/O side effects;
callers decide where output goes.
"""

from .client import SurveyDefinition

SEPARATOR = "-" * 72


def format_survey_report(definition: SurveyDefinition) -> str:
    """Render a survey definition as a human-readable inspection report.

    Args:
        definition: Parsed survey definition from the API.

    Returns:
        Multi-line string suitable for printing or writing to a file.
    """
    lines: list[str] = [
        SEPARATOR,
        f"Survey: {definition.survey_name}",
        f"ID:     {definition.survey_id}",
        f"Questions: {len(definition.questions)}",
        SEPARATOR,
    ]

    for q in definition.questions:
        lines.append(
            f"  [{q.question_id}]  name={q.question_name}  type={q.question_type}"
        )
        cleaned = q.question_text.replace("\n", " ").strip()
        lines.append(f"    {cleaned}")
        lines.append("")

    return "\n".join(lines)
