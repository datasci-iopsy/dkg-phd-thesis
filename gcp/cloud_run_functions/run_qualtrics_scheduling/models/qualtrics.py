"""Pydantic models for Qualtrics webhook and API response payloads.

Three model groups live here:

1. WebServicePayload -- the POST body from a Qualtrics Workflow
    Web Service task, containing the full survey response with
    semantic field names and human-readable label values.

2. WebhookNotification / QualtricsResponse -- legacy models for
    the event subscription + API fetch pattern. Retained for
    manual lookups via qualtrics_utils.fetch_single_response().

3. Constants -- CONSENT_AGREE_VALUE, ELIGIBILITY_YES_VALUE, and
    SCALE_FIELDS used by validation and test code.

The QID_MAP constant provides the single-source mapping between
opaque Qualtrics question IDs and semantic field names used
throughout the codebase. Update it here when survey questions
change -- nothing else should hard-code QID strings.
"""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field

# -- QID field mapping -----------------------------------------------
# Maps semantic names -> Qualtrics question IDs.
# Organized by category. The rest of the codebase references the
# semantic name on the left; only this dict knows the QID strings.
#
# To update: change the QID string on the right when Qualtrics
# question IDs change.

QID_MAP: dict[str, str] = {
    # -- Consent & identification ------------------------------------
    "consent": "QID31",
    "prolific_pid": "QID3_TEXT",
    # -- Eligibility flags -------------------------------------------
    "age_flag": "QID44",
    "fte_flag": "QID41",
    "location_flag": "QID43",
    "language_flag": "QID45",
    # -- Scheduling --------------------------------------------------
    "phone": "QID42_TEXT",
    "timezone": "QID30",
    "selected_date": "QID29_TEXT",
    # -- Demographics ------------------------------------------------
    "age": "QID35_TEXT",
    "ethnicity": "QID36",
    "gender_identity": "QID37",
    "job_tenure": "QID38",
    "education_level": "QID39",
    "remote_flag": "QID40",
    # -- Positive Affect (PA1-PA5) -----------------------------------
    "PA1": "QID76",
    "PA2": "QID80",
    "PA3": "QID79",
    "PA4": "QID78",
    "PA5": "QID77",
    # -- Negative Affect (NA1-NA5) -----------------------------------
    "NA1": "QID84",
    "NA2": "QID83",
    "NA3": "QID82",
    "NA4": "QID81",
    "NA5": "QID85",
    # -- Psychological Breach (BR1-BR5) ------------------------------
    "BR1": "QID66",
    "BR2": "QID67",
    "BR3": "QID68",
    "BR4": "QID69",
    "BR5": "QID75",
    # -- Psychological Violation (VIO1-VIO4) -------------------------
    "VIO1": "QID70",
    "VIO2": "QID71",
    "VIO3": "QID74",
    "VIO4": "QID73",
    # -- Job Satisfaction --------------------------------------------
    "JS1": "QID91",
}

# -- Label constants -------------------------------------------------
# The Web Service task sends human-readable labels (e.g., "Yes")
# rather than integer recode values. These constants define the
# label strings that indicate consent and eligibility.

CONSENT_AGREE_VALUE: str = "Yes"
ELIGIBILITY_YES_VALUE: str = "Yes"

# -- Scale field names -----------------------------------------------
# Tuple of all psychometric scale field names for iteration.
# PA(5) + NA(5) + BR(5) + VIO(4) + JS(1) = 20 items.
SCALE_FIELDS: tuple[str, ...] = (
    "PA1",
    "PA2",
    "PA3",
    "PA4",
    "PA5",
    "NA1",
    "NA2",
    "NA3",
    "NA4",
    "NA5",
    "BR1",
    "BR2",
    "BR3",
    "BR4",
    "BR5",
    "VIO1",
    "VIO2",
    "VIO3",
    "VIO4",
    "JS1",
)


# -- Web Service payload (Qualtrics Workflow -> our endpoint) --------
class WebServicePayload(BaseModel):
    """Full survey response from a Qualtrics Web Service task.

    Field names use the semantic names from QID_MAP, matching
    the JSON keys in the Qualtrics Workflow Web Service template.

    All fields store human-readable label text (strings) as sent
    by the Web Service task using Qualtrics SelectedChoices piped
    text. The only integer field is 'age', which is a numeric
    text entry rather than a coded choice.

    Only response_id and survey_id are required. All other fields
    are optional (nullable) because Qualtrics survey logic may
    route participants to the end of the survey early if they
    fail screening or attention checks.

    When the survey changes:
        1. Update QID_MAP above.
        2. Add/remove fields on this model.
        3. Update the Web Service JSON template in Qualtrics.
        4. The BigQuery schema regenerates automatically.
    """

    # -- System identifiers (REQUIRED) -------------------------------
    response_id: str = Field(
        ..., description="Qualtrics response identifier (e.g., R_1KNaaa...)"
    )
    survey_id: str = Field(
        ..., description="Qualtrics survey identifier (e.g., SV_86vM...)"
    )
    # -- Consent & identification ------------------------------------
    consent: str | None = Field(
        default=None, description="Consent label; 'Yes' = agreed"
    )
    prolific_pid: str | None = Field(
        default=None, description="Prolific participant identifier (free text)"
    )
    # -- Eligibility flags (label: 'Yes' or 'No') -------------------
    age_flag: str | None = Field(
        default=None,
        description="Age eligibility label; 'Yes' = meets criteria",
    )
    fte_flag: str | None = Field(
        default=None,
        description="Full-time employment label; 'Yes' = meets criteria",
    )
    location_flag: str | None = Field(
        default=None,
        description="Location eligibility label; 'Yes' = meets criteria",
    )
    language_flag: str | None = Field(
        default=None,
        description="Language eligibility label; 'Yes' = meets criteria",
    )
    # -- Scheduling --------------------------------------------------
    phone: str | None = Field(
        default=None, description="Raw phone digits from survey text entry"
    )
    timezone: str | None = Field(
        default=None, description="Timezone label (e.g., US/Central)"
    )
    selected_date: str | None = Field(
        default=None,
        description="Scheduling date as MM/DD/YYYY from Qualtrics",
    )
    # -- Demographics ------------------------------------------------
    age: int | None = Field(
        default=None, description="Participant age (numeric text entry)"
    )
    ethnicity: str | None = Field(
        default=None, description="Ethnicity label (e.g., Asian)"
    )
    gender_identity: str | None = Field(
        default=None, description="Gender identity label (e.g., Non-binary)"
    )
    job_tenure: str | None = Field(
        default=None, description="Job tenure label (e.g., 3 to 5 years)"
    )
    education_level: str | None = Field(
        default=None, description="Education label (e.g., Bachelor's degree)"
    )
    remote_flag: str | None = Field(
        default=None, description="Remote work label (e.g., Yes)"
    )
    # -- Positive Affect (PA1-PA5) -----------------------------------
    PA1: str | None = Field(default=None, description="Alert (label)")
    PA2: str | None = Field(default=None, description="Inspired (label)")
    PA3: str | None = Field(default=None, description="Determined (label)")
    PA4: str | None = Field(default=None, description="Attentive (label)")
    PA5: str | None = Field(default=None, description="Active (label)")
    # -- Negative Affect (NA1-NA5) -----------------------------------
    NA1: str | None = Field(default=None, description="Upset (label)")
    NA2: str | None = Field(default=None, description="Hostile (label)")
    NA3: str | None = Field(default=None, description="Ashamed (label)")
    NA4: str | None = Field(default=None, description="Nervous (label)")
    NA5: str | None = Field(default=None, description="Afraid (label)")
    # -- Psychological Breach (BR1-BR5) ------------------------------
    BR1: str | None = Field(default=None, description="Breach item 1 (label)")
    BR2: str | None = Field(default=None, description="Breach item 2 (label)")
    BR3: str | None = Field(default=None, description="Breach item 3 (label)")
    BR4: str | None = Field(default=None, description="Breach item 4 (label)")
    BR5: str | None = Field(default=None, description="Breach item 5 (label)")
    # -- Psychological Violation (VIO1-VIO4) -------------------------
    VIO1: str | None = Field(
        default=None, description="Violation item 1 (label)"
    )
    VIO2: str | None = Field(
        default=None, description="Violation item 2 (label)"
    )
    VIO3: str | None = Field(
        default=None, description="Violation item 3 (label)"
    )
    VIO4: str | None = Field(
        default=None, description="Violation item 4 (label)"
    )
    # -- Job Satisfaction --------------------------------------------
    JS1: str | None = Field(
        default=None, description="Job satisfaction item 1 (label)"
    )


# -- Webhook notification (Qualtrics -> our endpoint) ----------------
class WebhookNotification(BaseModel):
    """Payload Qualtrics POSTs when a survey response is completed.

    Field names use PascalCase to match the Qualtrics event
    subscription contract exactly. Retained for reference; the
    active pipeline uses WebServicePayload.
    """

    Topic: str
    Status: str | None = None
    SurveyID: str
    ResponseID: str
    BrandID: str | None = None
    CompletedDate: str | None = None


# -- API response (our GET to Qualtrics) -----------------------------
class ResponseMeta(BaseModel):
    """Metadata envelope from the Qualtrics API."""

    requestId: str
    httpStatus: str


class SurveyResult(BaseModel):
    """Single survey response returned by the Qualtrics API.

    `values` contains raw response data keyed by QID. Types are
    mixed -- ints for coded choices, strings for free-text fields.

    `labels` contains human-readable labels for coded values
    (e.g., QID30=12 -> "US/Central"). Only coded fields appear
    here; free-text fields do not.

    Retained for manual API lookups; the active pipeline uses
    WebServicePayload.
    """

    responseId: str
    values: dict[str, Any]
    labels: dict[str, str] = Field(default_factory=dict)
    displayedFields: list[str] = Field(default_factory=list)
    displayedValues: dict[str, Any] = Field(default_factory=dict)


class QualtricsResponse(BaseModel):
    """Top-level envelope for the 'Retrieve a Survey Response' API.

    API reference:
        https://api.qualtrics.com/1179a68b7183c-retrieve-a-survey-response

    Retained for manual API lookups; the active pipeline uses
    WebServicePayload.
    """

    result: SurveyResult
    meta: ResponseMeta
