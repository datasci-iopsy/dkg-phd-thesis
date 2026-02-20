"""
Tests for Qualtrics response models and participant extraction.

Uses fixture files to verify that:
  - WebServicePayload parses and validates correctly
  - WebServicePayload accepts partial payloads (failed screening)
  - Phone normalization handles common formats
  - ParticipantData validates good data and rejects bad data
  - QID_MAP field names align with WebServicePayload field names
  - The full extraction pipeline works end-to-end

Usage from project root:
    poetry run pytest gcp/tests/test_models.py -v
"""

import json
from datetime import date, datetime
from pathlib import Path

import pytest
from models.participant import ParticipantData, normalize_phone_number
from models.qualtrics import (
    CONSENT_AGREE_VALUE,
    ELIGIBILITY_YES_VALUE,
    QID_MAP,
    SCALE_FIELDS,
    WebServicePayload,
)

# -- Fixture loading -------------------------------------------------
FIXTURES_DIR = Path(__file__).resolve().parent / "fixtures"


@pytest.fixture
def raw_web_service_json() -> dict:
    """Load the Web Service task payload fixture from disk."""
    path = FIXTURES_DIR / "web_service_payload.json"
    return json.loads(path.read_text())


@pytest.fixture
def web_service_payload(raw_web_service_json) -> WebServicePayload:
    """Parse the fixture into a validated WebServicePayload."""
    return WebServicePayload.model_validate(raw_web_service_json)


# -- WebServicePayload model tests -----------------------------------
class TestWebServicePayload:
    """Verify the Web Service task payload parses and validates."""

    def test_parses_fixture(self, web_service_payload):
        assert web_service_payload.response_id == "R_2LObbbYBNZqyuhX"
        assert web_service_payload.survey_id == "SV_86vMYNR8SdVDfEi"

    def test_consent_field(self, web_service_payload):
        assert web_service_payload.consent == CONSENT_AGREE_VALUE
        assert web_service_payload.consent == "Yes"

    def test_scheduling_fields(self, web_service_payload):
        assert web_service_payload.phone == "8777804236"
        assert web_service_payload.timezone == "US/Central"
        assert web_service_payload.selected_date == "12/26/2025"

    def test_eligibility_flags(self, web_service_payload):
        assert web_service_payload.age_flag == ELIGIBILITY_YES_VALUE
        assert web_service_payload.fte_flag == ELIGIBILITY_YES_VALUE
        assert web_service_payload.location_flag == ELIGIBILITY_YES_VALUE
        assert web_service_payload.language_flag == ELIGIBILITY_YES_VALUE

    def test_demographic_labels(self, web_service_payload):
        assert web_service_payload.ethnicity == "Asian"
        assert web_service_payload.gender_identity == "Non-binary"
        assert web_service_payload.job_tenure == "3 to 5 years"
        assert web_service_payload.education_level == "Bachelor's degree"
        assert web_service_payload.remote_flag == "Yes"

    def test_age_is_integer(self, web_service_payload):
        """Age is the only integer field -- numeric text entry."""
        assert isinstance(web_service_payload.age, int)
        assert web_service_payload.age == 30

    def test_scale_items_are_labels(self, web_service_payload):
        """All scale items must be label strings in a full payload."""
        data = web_service_payload.model_dump()
        for field in SCALE_FIELDS:
            assert isinstance(data[field], str), (
                f"Scale item '{field}' should be str, "
                f"got {type(data[field]).__name__}: {data[field]}"
            )

    def test_scale_item_count(self):
        """Verify SCALE_FIELDS has the expected count."""
        # PA(5) + NA(5) + BR(5) + VIO(4) + JS(1) = 20
        assert len(SCALE_FIELDS) == 20

    def test_positive_affect_labels(self, web_service_payload):
        """PA items use the PANAS frequency scale."""
        valid_pa_labels = {
            "Never",
            "Rather infrequently",
            "Some of the time",
            "Quite often",
            "Always",
        }
        for field in ("PA1", "PA2", "PA3", "PA4", "PA5"):
            value = getattr(web_service_payload, field)
            assert value in valid_pa_labels, (
                f"{field} = '{value}' not in valid PA labels"
            )

    def test_negative_affect_labels(self, web_service_payload):
        """NA items use the PANAS frequency scale."""
        valid_na_labels = {
            "Never",
            "Rather infrequently",
            "Some of the time",
            "Quite often",
            "Always",
        }
        for field in ("NA1", "NA2", "NA3", "NA4", "NA5"):
            value = getattr(web_service_payload, field)
            assert value in valid_na_labels, (
                f"{field} = '{value}' not in valid NA labels"
            )

    def test_breach_violation_labels(self, web_service_payload):
        """BR and VIO items use the Likert agreement scale."""
        valid_likert_labels = {
            "Strongly disagree",
            "Disagree",
            "Neither agree nor disagree",
            "Agree",
            "Strongly agree",
        }
        for field in (
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
        ):
            value = getattr(web_service_payload, field)
            assert value in valid_likert_labels, (
                f"{field} = '{value}' not in valid Likert labels"
            )

    def test_model_dump_round_trips(self, raw_web_service_json):
        """model_validate -> model_dump should preserve all values."""
        payload = WebServicePayload.model_validate(raw_web_service_json)
        dumped = payload.model_dump()
        for key, value in raw_web_service_json.items():
            assert dumped[key] == value, (
                f"Round-trip mismatch on '{key}': "
                f"expected {value!r}, got {dumped[key]!r}"
            )

    def test_rejects_missing_response_id(self, raw_web_service_json):
        del raw_web_service_json["response_id"]
        with pytest.raises(Exception):
            WebServicePayload.model_validate(raw_web_service_json)

    def test_rejects_missing_survey_id(self, raw_web_service_json):
        del raw_web_service_json["survey_id"]
        with pytest.raises(Exception):
            WebServicePayload.model_validate(raw_web_service_json)

    def test_rejects_non_integer_age(self, raw_web_service_json):
        """Age must be an integer, not an arbitrary string."""
        raw_web_service_json["age"] = "thirty"
        with pytest.raises(Exception):
            WebServicePayload.model_validate(raw_web_service_json)


# -- Partial payload tests -------------------------------------------
class TestPartialPayload:
    """Verify WebServicePayload accepts incomplete responses.

    When Qualtrics survey logic routes a participant to the end
    early (failed screening, attention check), only some fields
    are populated. All fields except response_id and survey_id
    are optional.
    """

    def test_minimal_payload(self):
        """Only response_id and survey_id are required."""
        payload = WebServicePayload(
            response_id="R_partial_001",
            survey_id="SV_test456",
        )
        assert payload.response_id == "R_partial_001"
        assert payload.consent is None
        assert payload.PA1 is None
        assert payload.age is None

    def test_partial_with_consent_and_screening(self):
        """Failed screening: consent given but eligibility failed."""
        payload = WebServicePayload(
            response_id="R_partial_002",
            survey_id="SV_test456",
            consent="Yes",
            age_flag="No",
        )
        assert payload.consent == "Yes"
        assert payload.age_flag == "No"
        assert payload.phone is None
        assert payload.PA1 is None

    def test_missing_optional_field_is_none(self, raw_web_service_json):
        """Removing an optional field results in None, not an error."""
        del raw_web_service_json["PA1"]
        payload = WebServicePayload.model_validate(raw_web_service_json)
        assert payload.PA1 is None
        # Other fields still populated
        assert payload.PA2 == "Quite often"

    def test_null_age_accepted(self):
        """Age field accepts None (participant skipped)."""
        payload = WebServicePayload(
            response_id="R_test",
            survey_id="SV_test",
            age=None,
        )
        assert payload.age is None


# -- QID_MAP <-> WebServicePayload alignment -------------------------
class TestQIDMapAlignment:
    """Verify QID_MAP semantic names match WebServicePayload fields.

    The Web Service JSON template uses QID_MAP's left-side names
    as JSON keys, so the two must stay in sync. This catches drift
    when one is updated without the other.
    """

    def test_all_qid_map_names_are_payload_fields(self):
        """Every semantic name in QID_MAP must exist as a field
        on WebServicePayload.
        """
        payload_fields = set(WebServicePayload.model_fields.keys())
        for semantic_name in QID_MAP:
            assert semantic_name in payload_fields, (
                f"QID_MAP key '{semantic_name}' has no matching field "
                f"on WebServicePayload"
            )


# -- normalize_phone_number tests ------------------------------------
class TestNormalizePhone:
    """Verify phone normalization to E.164 format."""

    def test_ten_digit_us(self):
        assert normalize_phone_number("8777804236") == "+18777804236"

    def test_ten_digit_with_formatting(self):
        assert normalize_phone_number("(984) 555-7878") == "+19845557878"

    def test_eleven_digit_with_leading_one(self):
        assert normalize_phone_number("18777804236") == "+18777804236"

    def test_already_e164(self):
        assert normalize_phone_number("+18777804236") == "+18777804236"

    def test_empty_returns_none(self):
        assert normalize_phone_number("") is None

    def test_whitespace_only_returns_none(self):
        assert normalize_phone_number("   ") is None

    def test_too_few_digits_returns_none(self):
        assert normalize_phone_number("12345") is None


# -- ParticipantData model tests -------------------------------------
class TestParticipantData:
    """Verify Pydantic validation on the participant model."""

    @pytest.fixture
    def valid_kwargs(self) -> dict:
        """Minimal valid construction arguments."""
        return {
            "response_id": "R_test123",
            "prolific_pid": "60a7c1b2e3f4a5b6c7d8e9f0",
            "phone": "+18777804236",
            "selected_date": date(2025, 12, 26),
            "timezone": "US/Central",
            "consent_given": True,
        }

    def test_valid_construction(self, valid_kwargs):
        p = ParticipantData(**valid_kwargs)
        assert p.prolific_pid == "60a7c1b2e3f4a5b6c7d8e9f0"
        assert p.phone == "+18777804236"
        assert p.consent_given is True
        assert isinstance(p.created_at, datetime)

    def test_pid_is_stripped(self, valid_kwargs):
        valid_kwargs["prolific_pid"] = "  60a7c1b2e3f4a5b6c7d8e9f0  "
        p = ParticipantData(**valid_kwargs)
        assert p.prolific_pid == "60a7c1b2e3f4a5b6c7d8e9f0"

    def test_phone_masked(self, valid_kwargs):
        p = ParticipantData(**valid_kwargs)
        assert p.phone_masked == "+1***4236"

    def test_followup_times(self, valid_kwargs):
        p = ParticipantData(**valid_kwargs)
        assert len(p.followup_times) == 3

    def test_rejects_blank_pid(self, valid_kwargs):
        valid_kwargs["prolific_pid"] = "   "
        with pytest.raises(Exception, match="[Pp]rolific|blank"):
            ParticipantData(**valid_kwargs)

    def test_rejects_bad_phone_format(self, valid_kwargs):
        valid_kwargs["phone"] = "8777804236"
        with pytest.raises(Exception, match="E.164"):
            ParticipantData(**valid_kwargs)

    def test_rejects_no_consent(self, valid_kwargs):
        valid_kwargs["consent_given"] = False
        with pytest.raises(Exception, match="[Cc]onsent"):
            ParticipantData(**valid_kwargs)

    def test_rejects_empty_timezone(self, valid_kwargs):
        valid_kwargs["timezone"] = ""
        with pytest.raises(Exception):
            ParticipantData(**valid_kwargs)


# -- Full extraction pipeline test -----------------------------------
class TestExtractionPipeline:
    """End-to-end: Web Service payload -> normalize -> ParticipantData.

    Mirrors the logic in validation_utils.extract_participant_data()
    to prove the models work independently.
    """

    def test_extract_participant_from_web_service_payload(
        self, web_service_payload
    ):
        phone = normalize_phone_number(web_service_payload.phone)
        assert phone is not None

        consent = web_service_payload.consent == CONSENT_AGREE_VALUE

        month, day, year = web_service_payload.selected_date.split("/")
        selected_date = date(int(year), int(month), int(day))

        participant = ParticipantData(
            response_id=web_service_payload.response_id,
            prolific_pid=web_service_payload.prolific_pid,
            phone=phone,
            selected_date=selected_date,
            timezone=web_service_payload.timezone,
            consent_given=consent,
        )

        assert participant.response_id == "R_2LObbbYBNZqyuhX"
        assert participant.prolific_pid == "dkgdkgdkgdkgdkgdkgdkgdkg"
        assert participant.phone == "+18777804236"
        assert participant.selected_date == date(2025, 12, 26)
        assert participant.timezone == "US/Central"
        assert participant.consent_given is True

    def test_non_consenting_response_rejected(self, raw_web_service_json):
        """If consent != 'Yes', construction must fail."""
        raw_web_service_json["consent"] = "No"
        payload = WebServicePayload.model_validate(raw_web_service_json)
        consent = payload.consent == CONSENT_AGREE_VALUE
        assert consent is False

        with pytest.raises(Exception, match="[Cc]onsent"):
            ParticipantData(
                response_id=payload.response_id,
                prolific_pid="test_pid",
                phone="+18777804236",
                selected_date=date(2025, 12, 26),
                timezone="US/Central",
                consent_given=consent,
            )
