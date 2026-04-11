"""Pydantic models for followup survey Web Service payloads.

Mirrors the pattern in run_qualtrics_scheduling/models/qualtrics.py.
All three daily followup surveys (9AM/1PM/5PM) share this schema;
the `timepoint` field (1/2/3) differentiates them.

The QID_MAP constant provides the single-source mapping between
Qualtrics question IDs and semantic field names. The Qualtrics
Web Service task JSON template uses the UPPERCASE field names as
keys (matching the AliasGenerator below).
"""

from __future__ import annotations

from typing import Any

from pydantic import (
    AliasGenerator,
    BaseModel,
    ConfigDict,
    Field,
    model_validator,
)

# -- QID field mapping -----------------------------------------------
# Maps semantic names -> Qualtrics question IDs.
# Used to document the Web Service task JSON template structure.

QID_MAP: dict[str, str] = {
    # -- Survey metadata (embedded data) -----------------------------
    "response_id": "ResponseID",
    "survey_id": "SurveyID",
    "intake_response_id": "response_id",
    "duration": "Q_TotalDuration",
    "timepoint": "survey_time",
    "connect_id": "connect_id",
    # -- Identification (question) -----------------------------------
    "phone_number": "QID51_TEXT",
    # -- Burnout: Physical Fatigue (PF1-PF6) -------------------------
    "pf1": "QID6",
    "pf2": "QID9",
    "pf3": "QID50",
    "pf4": "QID11",
    "pf5": "QID12",
    "pf6": "QID13",
    # -- Burnout: Cognitive Weariness (CW1-CW5) ----------------------
    "cw1": "QID14",
    "cw2": "QID15",
    "cw3": "QID16",
    "cw4": "QID17",
    "cw5": "QID18",
    # -- Burnout: Emotional Exhaustion (EE1-EE3) ---------------------
    "ee1": "QID20",
    "ee2": "QID21",
    "ee3": "QID22",
    # -- Need Frustration: Competency Thwarting (COMP1-COMP4) --------
    "comp1": "QID23",
    "comp2": "QID24",
    "comp3": "QID26",
    "comp4": "QID25",
    # -- Need Frustration: Autonomy Thwarting (AUTO1-AUTO4) ----------
    "auto1": "QID29",
    "auto2": "QID30",
    "auto3": "QID31",
    "auto4": "QID32",
    # -- Need Frustration: Relatedness Thwarting (RELT1-RELT4) -------
    "relt1": "QID34",
    "relt2": "QID35",
    "relt3": "QID36",
    "relt4": "QID37",
    # -- Marker variable: Attitude Toward Color Blue -----------------
    "atcb2": "QID39",
    "atcb5": "QID42",
    "atcb6": "QID43",
    "atcb7": "QID44",
    # -- Attention check ---------------------------------------------
    "attention_check": "QID46",
    # -- Meeting context ---------------------------------------------
    "meetings_num": "QID45_TEXT",
    "meetings_time": "QID48_1",
    # -- Turnover intention ------------------------------------------
    "turnover_intention": "QID5",
}

# -- Scale field names -----------------------------------------------
# All psychometric scale field names for iteration.
# PF(6) + CW(5) + EE(3) + COMP(4) + AUTO(4) + RELT(4) + ATCB(4) = 30 items
# Plus turnover_intention = 31 items
FOLLOWUP_SCALE_FIELDS: tuple[str, ...] = (
    "pf1",
    "pf2",
    "pf3",
    "pf4",
    "pf5",
    "pf6",
    "cw1",
    "cw2",
    "cw3",
    "cw4",
    "cw5",
    "ee1",
    "ee2",
    "ee3",
    "comp1",
    "comp2",
    "comp3",
    "comp4",
    "auto1",
    "auto2",
    "auto3",
    "auto4",
    "relt1",
    "relt2",
    "relt3",
    "relt4",
    "atcb2",
    "atcb5",
    "atcb6",
    "atcb7",
    "turnover_intention",
)


# -- Web Service payload (Qualtrics Workflow -> our endpoint) --------
class FollowupWebServicePayload(BaseModel):
    """Full followup survey response from a Qualtrics Web Service task.

    All three daily surveys (9AM/1PM/5PM) share this schema. The
    `timepoint` field (1/2/3) distinguishes them, captured from the
    `survey_time` URL query parameter via Qualtrics embedded data.

    The `intake_response_id` links this response back to the intake
    survey that triggered scheduling. It is the `response_id` passed
    as a URL query param by run_followup_scheduling.

    Field names use lowercase, matching the target BigQuery schema.
    The AliasGenerator accepts UPPERCASE keys from the Qualtrics
    Web Service task (e.g., ``CONNECT_ID``) while keeping lowercase
    Python field names. ``populate_by_name=True`` lets tests and
    internal code construct the model directly without aliases.

    Only response_id and survey_id are required. All other fields
    are optional because participants may exit the survey early.
    """

    model_config = ConfigDict(
        alias_generator=AliasGenerator(
            validation_alias=lambda name: name.upper()
        ),
        populate_by_name=True,
        coerce_numbers_to_str=True,
    )

    @model_validator(mode="before")
    @classmethod
    def _coerce_empty_strings(cls, data: Any) -> Any:
        """Convert empty strings to None before field validation.

        Qualtrics Web Service tasks send '' for unanswered questions
        and unresolved embedded data piped text. Integer fields
        (duration, timepoint, meetings_num, meetings_time) cannot
        parse '' -- this validator normalises them to None first.
        """
        if not isinstance(data, dict):
            return data
        return {k: (None if v == "" else v) for k, v in data.items()}

    # -- System identifiers (REQUIRED) -------------------------------
    response_id: str = Field(
        ...,
        description=("Followup survey's own Qualtrics response identifier"),
    )
    survey_id: str = Field(
        ..., description="Qualtrics survey identifier for this timepoint"
    )
    # -- Response metadata -------------------------------------------
    intake_response_id: str | None = Field(
        default=None,
        description=(
            "Intake survey response_id passed via URL param; "
            "join key to stg_intake_responses"
        ),
    )
    duration: int | None = Field(
        default=None,
        description="Survey completion duration in seconds",
    )
    timepoint: int | None = Field(
        default=None,
        description="Survey time slot: 1=9AM, 2=1PM, 3=5PM",
    )
    connect_id: str | None = Field(
        default=None,
        description="CloudConnect participant ID (primary join key)",
    )
    phone_number: str | None = Field(
        default=None,
        description="Raw phone digits (secondary join key)",
    )
    # -- Burnout: Physical Fatigue -----------------------------------
    pf1: str | None = Field(
        default=None,
        description="I have felt tired (label)",
    )
    pf2: str | None = Field(
        default=None,
        description="I have been lacking energy for my work (label)",
    )
    pf3: str | None = Field(
        default=None,
        description="I have felt physically drained (label)",
    )
    pf4: str | None = Field(
        default=None,
        description="I have felt fed-up (label)",
    )
    pf5: str | None = Field(
        default=None,
        description="I felt like my batteries are dead (label)",
    )
    pf6: str | None = Field(
        default=None,
        description="I have felt burned out (label)",
    )
    # -- Burnout: Cognitive Weariness --------------------------------
    cw1: str | None = Field(
        default=None,
        description="My thinking process has been slow (label)",
    )
    cw2: str | None = Field(
        default=None,
        description="I have had difficulty concentrating (label)",
    )
    cw3: str | None = Field(
        default=None,
        description="I have felt like I am not thinking clearly (label)",
    )
    cw4: str | None = Field(
        default=None,
        description="I have felt like I am not focused on my thinking (label)",
    )
    cw5: str | None = Field(
        default=None,
        description=(
            "I have had difficulty thinking about complex things (label)"
        ),
    )
    # -- Burnout: Emotional Exhaustion -------------------------------
    ee1: str | None = Field(
        default=None,
        description=(
            "Unable to respond sensitively to coworkers or customers (label)"
        ),
    )
    ee2: str | None = Field(
        default=None,
        description=(
            "Incapable of investing emotionally in coworkers or customers"
            " (label)"
        ),
    )
    ee3: str | None = Field(
        default=None,
        description=(
            "Incapable of being sympathetic to coworkers or customers (label)"
        ),
    )
    # -- Need Frustration: Competency Thwarting ----------------------
    comp1: str | None = Field(
        default=None,
        description=(
            "Felt incompetent due to unrealistic expectations (label)"
        ),
    )
    comp2: str | None = Field(
        default=None,
        description="Told things that made me feel incompetent (label)",
    )
    comp3: str | None = Field(
        default=None,
        description="Made to feel inadequate (label)",
    )
    comp4: str | None = Field(
        default=None,
        description="Felt inadequate due to lack of opportunities (label)",
    )
    # -- Need Frustration: Autonomy Thwarting ------------------------
    auto1: str | None = Field(
        default=None,
        description="Prevented from making choices about work (label)",
    )
    auto2: str | None = Field(
        default=None,
        description="Pushed to behave in certain ways (label)",
    )
    auto3: str | None = Field(
        default=None,
        description="Obligated to follow work decisions made for me (label)",
    )
    auto4: str | None = Field(
        default=None,
        description=(
            "Under pressure to agree with work regimen provided (label)"
        ),
    )
    # -- Need Frustration: Relatedness Thwarting ---------------------
    relt1: str | None = Field(
        default=None,
        description="Felt rejected by those around me (label)",
    )
    relt2: str | None = Field(
        default=None,
        description="Felt dismissed by others (label)",
    )
    relt3: str | None = Field(
        default=None,
        description="Felt like other people dislike me (label)",
    )
    relt4: str | None = Field(
        default=None,
        description="Felt coworkers got jealous of my work (label)",
    )
    # -- Marker variable: Attitude Toward Color Blue -----------------
    atcb2: str | None = Field(
        default=None,
        description="Blue is a lovely color (label)",
    )
    atcb5: str | None = Field(
        default=None,
        description="Blue is a nice color (label)",
    )
    atcb6: str | None = Field(
        default=None,
        description="I think blue is a pretty color (label)",
    )
    atcb7: str | None = Field(
        default=None,
        description="I like the color blue (label)",
    )
    # -- Attention check ---------------------------------------------
    attention_check: str | None = Field(
        default=None,
        description=(
            "Instructed response item; correct answer is 'Once' (label)"
        ),
    )
    # -- Meeting context ---------------------------------------------
    meetings_num: int | None = Field(
        default=None,
        description="Number of meetings attended since timepoint stem",
    )
    meetings_time: int | None = Field(
        default=None,
        description="Minutes spent in meetings since timepoint stem",
    )
    # -- Turnover intention ------------------------------------------
    turnover_intention: str | None = Field(
        default=None,
        description=("How often felt desire to leave current employer (label)"),
    )
