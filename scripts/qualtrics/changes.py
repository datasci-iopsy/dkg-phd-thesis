"""Change manifest for the three followup survey wording updates.

Each QuestionChange targets a single (survey_id, question_id) pair.
When find_text is None, QuestionText is fully replaced with replace_text.
When find_text is set, replace_text substitutes find_text within the existing text.
"""

from dataclasses import dataclass, field

P1 = "SV_5nV942MJGubDmqq"
P2 = "SV_eRKl4lgMZDAurT8"
P3 = "SV_6J3svun1r97AAHc"


@dataclass(frozen=True)
class QuestionChange:
    survey_id: str
    question_id: str
    replace_text: str
    find_text: str | None = None
    description: str = field(default="")


def _shared(
    question_id: str, replace_text: str, description: str
) -> list[QuestionChange]:
    """Return one change per survey for the same QID and new text (P1, P2, P3)."""
    return [
        QuestionChange(
            survey_id=sid,
            question_id=question_id,
            replace_text=replace_text,
            description=description,
        )
        for sid in (P1, P2, P3)
    ]


CHANGES: list[QuestionChange] = [
    # --- Physical Fatigue ---
    *_shared("QID9", "I have lacked energy for my work.", "PF2: tense fix"),
    *_shared("QID11", "I have felt fed up.", "PF4: remove hyphen"),
    *_shared(
        "QID12",
        "I have felt as though my batteries were dead.",
        "PF5: tense and phrasing",
    ),
    # --- Cognitive Weariness ---
    *_shared(
        "QID16", "I have had difficulty thinking clearly.", "CW3: rephrase"
    ),
    *_shared("QID17", "My thinking has been unfocused.", "CW4: rephrase"),
    # --- Emotional Exhaustion ---
    *_shared(
        "QID20",
        "I have been unable to respond sensitively to the needs of coworkers or customers.",
        "EE1: remove leading I feel",
    ),
    *_shared(
        "QID21",
        "I feel I have been incapable of investing emotionally in coworkers or customers.",
        "EE2: add missing I",
    ),
    *_shared(
        "QID22",
        "I have been unsympathetic toward coworkers or customers.",
        "EE3: rephrase",
    ),
    # --- Competence ---
    *_shared(
        "QID23",
        "There have been occasions when I felt incompetent because others imposed unrealistic expectations on me.",
        "COMP1: where to when, tense",
    ),
    *_shared(
        "QID24",
        "There have been times when I was told things that made me feel incompetent.",
        "COMP2: tense fix",
    ),
    *_shared(
        "QID25",
        "I have felt inadequate because I have not been given opportunities to fulfill my potential.",
        "COMP4: tense fix",
    ),
    *_shared(
        "QID26",
        "There have been situations in which I have been made to feel inadequate.",
        "COMP3: where to in which",
    ),
    # --- Autonomy ---
    *_shared(
        "QID29",
        "I have felt prevented from making choices about how I do my work.",
        "AUTO1: regarding the way to about how",
    ),
    *_shared(
        "QID32",
        "I have felt under pressure to agree with the work regimen I have been provided.",
        "AUTO4: tense fix",
    ),
    # --- Relatedness ---
    *_shared(
        "QID37",
        "I have felt as though some of my coworkers became jealous when I completed my tasks.",
        "RELT4: got to became, remove work",
    ),
    # --- P1-specific ---
    QuestionChange(
        survey_id=P1,
        question_id="QID19",
        find_text="<i>S<b>ince",
        replace_text="<i><b>Since",
        description="STEM3: fix broken HTML tag",
    ),
    QuestionChange(
        survey_id=P1,
        question_id="QID52",
        find_text="I can say that I am satisfied my job.",
        replace_text="I am satisfied with my job.",
        description="JS1: remove I can say that, fix satisfied with",
    ),
    # --- P2-specific ---
    QuestionChange(
        survey_id=P2,
        question_id="QID33",
        find_text="Since the last survey check-in",
        replace_text="Since the first survey check-in",
        description="STEM3: last to first",
    ),
    QuestionChange(
        survey_id=P2,
        question_id="QID48",
        find_text="Since starting work today",
        replace_text="Since the first survey check-in",
        description="MEETINGS_TIME: fix temporal stem",
    ),
    QuestionChange(
        survey_id=P2,
        question_id="QID1721263568",
        find_text="I can say that I am satisfied my job.",
        replace_text="I am satisfied with my job.",
        description="JS1: remove I can say that, fix satisfied with",
    ),
    # --- P3-specific ---
    QuestionChange(
        survey_id=P3,
        question_id="QID5",
        find_text="check-in</b> how",
        replace_text="check-in</b>, how",
        description="TURNOVER_INTENTION: add missing comma",
    ),
    QuestionChange(
        survey_id=P3,
        question_id="QID48",
        find_text="Since starting work today",
        replace_text="Since the last survey check-in",
        description="MEETINGS_TIME: fix temporal stem",
    ),
    QuestionChange(
        survey_id=P3,
        question_id="QID1721263569",
        find_text="I can say that I am satisfied my job.",
        replace_text="I am satisfied with my job.",
        description="JS1: remove I can say that, fix satisfied with",
    ),
]
