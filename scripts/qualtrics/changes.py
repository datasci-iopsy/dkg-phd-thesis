"""Change manifest for the three followup survey wording updates.

Each QuestionChange targets a single (survey_id, question_id) pair.
When find_text is None, QuestionText is fully replaced with replace_text.
When find_text is set, replace_text substitutes find_text within the existing text.
"""

from dataclasses import dataclass, field

P1 = "SV_5nV942MJGubDmqq"
P2 = "SV_eRKl4lgMZDAurT8"
P3 = "SV_6J3svun1r97AAHc"
INTAKE = "SV_86vMYNR8SdVDfEi"

# QID for the work_shift question added in Slice C; referenced by the
# update runner to PUT the finalized 4-bin choices.
WORK_SHIFT_QID = "QID100"


@dataclass(frozen=True)
class QuestionAdd:
    survey_id: str
    question_body: dict
    field_name: str
    description: str = field(default="")


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
        "I have been unable to respond sensitively to coworkers or customers.",
        "EE1: trim 'the needs of'",
    ),
    *_shared(
        "QID21",
        "I have been incapable of investing emotionally in coworkers or customers.",
        "EE2: trim 'I feel'",
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
        "I have felt under pressure to agree with the work demands imposed on me.",
        "AUTO4: work regimen to work demands imposed on me",
    ),
    # --- Relatedness ---
    *_shared(
        "QID37",
        "I have felt as though some of my coworkers became envious when I did well at work.",
        "RELT4: jealous to envious, completed tasks to did well at work",
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

# -- Intake survey additions (Slice C) ----------------------------------
# These two questions are added to the intake survey draft.
# DO NOT publish the survey -- the user does that manually.
#
# work_shift choice labels use snake_case to match gcp_utils.yaml keys
# exactly. The web service payload will carry these strings as-is into
# the `work_shift` field, which routes fn3 delivery times.
# Update choice display text to human-readable labels before publishing.
INTAKE_ADDITIONS: list[QuestionAdd] = [
    QuestionAdd(
        survey_id=INTAKE,
        field_name="work_classification",
        description="DOL employment classification (stored for analysis)",
        question_body={
            "QuestionText": (
                "Which best describes your current employment classification?"
            ),
            "QuestionType": "MC",
            "Selector": "SAVR",
            "SubSelector": "TX",
            "Choices": {
                "1": {"Display": "Employee - Full-Time (40+ hrs/week)"},
                "2": {"Display": "Employee - Part-Time (<40 hrs/week)"},
                "3": {"Display": "Independent Contractor or Freelancer (1099)"},
                "4": {"Display": "Other"},
            },
            "ChoiceOrder": [1, 2, 3, 4],
        },
    ),
    QuestionAdd(
        survey_id=INTAKE,
        field_name="work_shift",
        description="Shift classification routes fn3 ESM delivery times",
        question_body={
            "QuestionText": (
                "Which best describes your typical work schedule "
                "on the day you selected?"
            ),
            "QuestionType": "MC",
            "Selector": "SAVR",
            "SubSelector": "TX",
            # Display values must stay snake_case: Qualtrics sends the Display
            # string verbatim in the Web Service payload, and get_followup_times
            # uses it as a direct key into config.shift_times.shifts.
            "Choices": {
                "1": {"Display": "early_shift"},
                "2": {"Display": "first_shift"},
                "3": {"Display": "second_shift"},
                "4": {"Display": "third_shift"},
            },
            "ChoiceOrder": [1, 2, 3, 4],
        },
    ),
]
