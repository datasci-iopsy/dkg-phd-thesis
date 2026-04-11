"""
Tests for the followup survey response pipeline.

Verifies:
  - FollowupWebServicePayload model validation and partial payloads
  - QID_MAP alignment with model field names
  - FOLLOWUP_RESPONSES_SCHEMA shape, column types, and system fields
  - _build_insert_row produces exactly FOLLOWUP_RESPONSES_COLUMNS
    with no _processed field (terminal table)
  - followup_response_handler returns 200/400/500 as appropriate

All BQ calls are mocked -- no credentials or network access needed.

Usage from project root:
    poetry run pytest gcp/tests/test_followup_response.py -v
"""

import importlib.util
import json
from pathlib import Path
from unittest.mock import patch

import pydantic
import pytest
from flask import Flask
from models.followup import (
    FOLLOWUP_SCALE_FIELDS,
    QID_MAP,
    FollowupWebServicePayload,
)
from shared.utils.bq_schemas import (
    FOLLOWUP_RESPONSES_CLUSTER_FIELDS,
    FOLLOWUP_RESPONSES_COLUMNS,
    FOLLOWUP_RESPONSES_SCHEMA,
    FOLLOWUP_SYSTEM_FIELDS,
)

# -- Import fn4 main via importlib ------------------------------------
# fn3's dir is inserted at sys.path[0] in conftest.py, so
# `from main import ...` would resolve to fn3's main.py instead.
# Use importlib with a unique module name to load fn4's main explicitly.

_FN4_DIR = (
    Path(__file__).parent.parent
    / "cloud_run_functions"
    / "run_followup_response"
)
_fn4_spec = importlib.util.spec_from_file_location(
    "run_followup_response_main", _FN4_DIR / "main.py"
)
_fn4_module = importlib.util.module_from_spec(_fn4_spec)
_fn4_spec.loader.exec_module(_fn4_module)

followup_response_handler = _fn4_module.followup_response_handler
_extract_followup_payload = _fn4_module._extract_followup_payload

# -- Shared test helpers ---------------------------------------------

FIXTURES_DIR = Path(__file__).resolve().parent / "fixtures"
_app = Flask(__name__)


@pytest.fixture
def raw_followup_json() -> dict:
    """Load the followup Web Service payload fixture from disk."""
    path = FIXTURES_DIR / "followup_web_service_payload.json"
    return json.loads(path.read_text())


@pytest.fixture
def followup_payload(raw_followup_json) -> FollowupWebServicePayload:
    return FollowupWebServicePayload.model_validate(raw_followup_json)


# -- Model validation tests ------------------------------------------
class TestFollowupWebServicePayload:
    """Verify the followup Web Service payload model."""

    def test_parses_fixture(self, followup_payload):
        assert followup_payload.response_id == "R_followup_test_001"
        assert followup_payload.survey_id == "SV_5nV942MJGubDmqq"

    def test_metadata_fields(self, followup_payload):
        assert followup_payload.intake_response_id == "R_2LObbbYBNZqyuhX"
        assert followup_payload.duration == 342
        assert followup_payload.timepoint == 1
        assert followup_payload.connect_id == "dkgdkgdkgdkgdkgdkgdkgdkg"
        assert followup_payload.phone_number == "8777804236"

    def test_numeric_fields_are_integers(self, followup_payload):
        assert isinstance(followup_payload.duration, int)
        assert isinstance(followup_payload.timepoint, int)
        assert isinstance(followup_payload.meetings_num, int)
        assert isinstance(followup_payload.meetings_time, int)

    def test_scale_items_are_strings(self, followup_payload):
        data = followup_payload.model_dump()
        for field in FOLLOWUP_SCALE_FIELDS:
            assert isinstance(data[field], str), (
                f"Scale item '{field}' should be str, "
                f"got {type(data[field]).__name__}: {data[field]}"
            )

    def test_attention_check_value(self, followup_payload):
        assert followup_payload.attention_check == "Once"

    def test_rejects_missing_response_id(self, raw_followup_json):
        del raw_followup_json["RESPONSE_ID"]
        with pytest.raises(pydantic.ValidationError):
            FollowupWebServicePayload.model_validate(raw_followup_json)

    def test_rejects_missing_survey_id(self, raw_followup_json):
        del raw_followup_json["SURVEY_ID"]
        with pytest.raises(pydantic.ValidationError):
            FollowupWebServicePayload.model_validate(raw_followup_json)

    def test_rejects_non_integer_duration(self, raw_followup_json):
        raw_followup_json["DURATION"] = "not_a_number"
        with pytest.raises(pydantic.ValidationError):
            FollowupWebServicePayload.model_validate(raw_followup_json)

    def test_rejects_non_integer_timepoint(self, raw_followup_json):
        raw_followup_json["TIMEPOINT"] = "one"
        with pytest.raises(pydantic.ValidationError):
            FollowupWebServicePayload.model_validate(raw_followup_json)


# -- Partial payload tests -------------------------------------------
class TestFollowupPartialPayload:
    """Verify model accepts partial responses (early survey exit).

    Only response_id and survey_id are required; all other fields
    are optional because participants may exit the survey early.
    """

    def test_minimal_payload(self):
        payload = FollowupWebServicePayload(
            response_id="R_partial_f001",
            survey_id="SV_5nV942MJGubDmqq",
        )
        assert payload.response_id == "R_partial_f001"
        assert payload.timepoint is None
        assert payload.connect_id is None
        assert payload.pf1 is None

    def test_missing_optional_field_is_none(self, raw_followup_json):
        del raw_followup_json["PF1"]
        payload = FollowupWebServicePayload.model_validate(raw_followup_json)
        assert payload.pf1 is None
        assert payload.pf2 == "Twice"

    def test_null_timepoint_accepted(self):
        payload = FollowupWebServicePayload(
            response_id="R_partial_f002",
            survey_id="SV_5nV942MJGubDmqq",
            timepoint=None,
        )
        assert payload.timepoint is None


# -- QID_MAP alignment tests -----------------------------------------
class TestQIDMapAlignment:
    """Verify QID_MAP names match FollowupWebServicePayload fields."""

    def test_all_qid_map_names_are_payload_fields(self):
        payload_fields = set(FollowupWebServicePayload.model_fields.keys())
        for semantic_name in QID_MAP:
            assert semantic_name in payload_fields, (
                f"QID_MAP key '{semantic_name}' has no matching field "
                f"on FollowupWebServicePayload"
            )

    def test_qid_map_count_matches_model_fields(self):
        """QID_MAP should cover all 41 model fields."""
        assert len(QID_MAP) == len(FollowupWebServicePayload.model_fields)


# -- Schema tests ----------------------------------------------------
class TestFollowupResponsesSchema:
    """Verify the generated followup_responses schema is well-formed."""

    def test_schema_is_not_empty(self):
        assert len(FOLLOWUP_RESPONSES_SCHEMA) > 0

    def test_column_count(self):
        """41 model fields + 1 system field (_created_at) = 42 columns."""
        expected = len(FollowupWebServicePayload.model_fields) + len(
            FOLLOWUP_SYSTEM_FIELDS
        )
        assert len(FOLLOWUP_RESPONSES_SCHEMA) == expected

    def test_no_duplicate_field_names(self):
        names = [f.name for f in FOLLOWUP_RESPONSES_SCHEMA]
        assert len(names) == len(set(names))

    def test_all_column_names_are_lowercase(self):
        for field in FOLLOWUP_RESPONSES_SCHEMA:
            assert field.name == field.name.lower()

    def test_created_at_present_and_required(self):
        field_map = {f.name: f for f in FOLLOWUP_RESPONSES_SCHEMA}
        assert "_created_at" in field_map
        assert field_map["_created_at"].field_type == "TIMESTAMP"
        assert field_map["_created_at"].mode == "REQUIRED"

    def test_no_processed_field(self):
        """Terminal table -- _processed must not be in the schema."""
        column_names = {f.name for f in FOLLOWUP_RESPONSES_SCHEMA}
        assert "_processed" not in column_names

    def test_system_fields_count(self):
        """Only _created_at -- one system field."""
        assert len(FOLLOWUP_SYSTEM_FIELDS) == 1
        assert FOLLOWUP_SYSTEM_FIELDS[0].name == "_created_at"

    def test_cluster_field_exists_in_schema(self):
        column_names = {f.name for f in FOLLOWUP_RESPONSES_SCHEMA}
        for field in FOLLOWUP_RESPONSES_CLUSTER_FIELDS:
            assert field in column_names

    def test_cluster_fields_value(self):
        assert FOLLOWUP_RESPONSES_CLUSTER_FIELDS == ["connect_id"]

    def test_integer_columns(self):
        """duration, timepoint, meetings_num, meetings_time are INTEGER."""
        field_map = {f.name: f for f in FOLLOWUP_RESPONSES_SCHEMA}
        integer_fields = sorted(
            name for name, f in field_map.items() if f.field_type == "INTEGER"
        )
        assert integer_fields == [
            "duration",
            "meetings_num",
            "meetings_time",
            "timepoint",
        ]

    def test_columns_set_matches_schema(self):
        schema_names = {f.name for f in FOLLOWUP_RESPONSES_SCHEMA}
        assert FOLLOWUP_RESPONSES_COLUMNS == schema_names

    def test_only_identifiers_are_required_model_fields(self):
        """Only response_id and survey_id are REQUIRED among model fields."""
        system_names = {f.name for f in FOLLOWUP_SYSTEM_FIELDS}
        required_model_fields = [
            f.name
            for f in FOLLOWUP_RESPONSES_SCHEMA
            if f.mode == "REQUIRED" and f.name not in system_names
        ]
        assert sorted(required_model_fields) == ["response_id", "survey_id"]


# -- Insert row tests ------------------------------------------------
class TestFollowupInsertRow:
    """Verify _build_insert_row produces exactly FOLLOWUP_RESPONSES_COLUMNS
    with no _processed field.
    """

    @pytest.fixture
    def sample_payload(self) -> FollowupWebServicePayload:
        return FollowupWebServicePayload(
            response_id="R_insert_test_001",
            survey_id="SV_5nV942MJGubDmqq",
            intake_response_id="R_2LObbbYBNZqyuhX",
            duration=342,
            timepoint=1,
            connect_id="test_connect_id",
            pf1="Once",
            meetings_num=3,
            meetings_time=90,
        )

    def test_insert_row_keys_match_schema(self, sample_payload):
        from shared.utils.gcp_utils import _build_insert_row

        row = _build_insert_row(sample_payload, FOLLOWUP_RESPONSES_SCHEMA)
        assert set(row.keys()) == FOLLOWUP_RESPONSES_COLUMNS

    def test_no_processed_key_in_row(self, sample_payload):
        """_processed must not appear in the insert row for followup table."""
        from shared.utils.gcp_utils import _build_insert_row

        row = _build_insert_row(sample_payload, FOLLOWUP_RESPONSES_SCHEMA)
        assert "_processed" not in row

    def test_created_at_present_in_row(self, sample_payload):
        from shared.utils.gcp_utils import _build_insert_row

        row = _build_insert_row(sample_payload, FOLLOWUP_RESPONSES_SCHEMA)
        assert "_created_at" in row

    def test_insert_row_keys_are_lowercase(self, sample_payload):
        from shared.utils.gcp_utils import _build_insert_row

        row = _build_insert_row(sample_payload, FOLLOWUP_RESPONSES_SCHEMA)
        for key in row:
            assert key == key.lower()

    def test_partial_payload_insert_keys_match_schema(self):
        from shared.utils.gcp_utils import _build_insert_row

        partial = FollowupWebServicePayload(
            response_id="R_partial_insert",
            survey_id="SV_5nV942MJGubDmqq",
        )
        row = _build_insert_row(partial, FOLLOWUP_RESPONSES_SCHEMA)
        assert set(row.keys()) == FOLLOWUP_RESPONSES_COLUMNS


# -- Handler integration tests ---------------------------------------
class TestFollowupResponseHandler:
    """Verify followup_response_handler HTTP responses.

    insert_survey_response is mocked -- no BQ credentials needed.
    """

    def test_valid_payload_returns_200(self, raw_followup_json):
        with patch.object(
            _fn4_module, "insert_survey_response", return_value=True
        ):
            with _app.test_request_context(
                "/followup",
                method="POST",
                content_type="application/json",
                data=json.dumps(raw_followup_json),
            ):
                from flask import request

                response, status = followup_response_handler(request)

        assert status == 200
        body = json.loads(response.get_data(as_text=True))
        assert body["status"] == "success"
        assert body["response_id"] == "R_followup_test_001"
        assert body["timepoint"] == 1

    def test_invalid_payload_returns_400(self):
        bad_payload = {"SURVEY_ID": "SV_5nV942MJGubDmqq"}
        with patch.object(
            _fn4_module, "insert_survey_response", return_value=True
        ) as mock_insert:
            with _app.test_request_context(
                "/followup",
                method="POST",
                content_type="application/json",
                data=json.dumps(bad_payload),
            ):
                from flask import request

                response, status = followup_response_handler(request)

        assert status == 400
        mock_insert.assert_not_called()

    def test_bq_failure_returns_500(self, raw_followup_json):
        with patch.object(
            _fn4_module, "insert_survey_response", return_value=False
        ):
            with _app.test_request_context(
                "/followup",
                method="POST",
                content_type="application/json",
                data=json.dumps(raw_followup_json),
            ):
                from flask import request

                response, status = followup_response_handler(request)

        assert status == 500

    def test_empty_body_returns_400(self):
        with _app.test_request_context(
            "/followup",
            method="POST",
            content_type="application/json",
            data="",
        ):
            from flask import request

            response, status = followup_response_handler(request)

        assert status == 400
