"""
Tests for BigQuery schema generation and consistency.

Since the schema is generated from the WebServicePayload Pydantic
model, alignment tests are unnecessary -- the schema cannot drift
from the model by construction. Instead, we test:

  - generate_schema() correctly maps Python types to BigQuery types
  - generate_schema() lowercases column names
  - generate_schema() unwraps Optional types correctly
  - Field descriptions are carried through from the Pydantic model
  - Unknown Python types raise a clear error
  - System fields are appended after model fields
  - The generated schema is well-formed (no duplicates, valid
    partition/cluster config)
  - The insert function writes exactly the columns in the schema

Usage from project root:
    poetry run pytest gcp/tests/test_bq_schemas.py -v
"""

import json

import pytest
from models.qualtrics import WebServicePayload
from pydantic import BaseModel, Field
from shared.utils.bq_schemas import (
    SURVEY_RESPONSES_CLUSTER_FIELDS,
    SURVEY_RESPONSES_COLUMNS,
    SURVEY_RESPONSES_PARTITION_FIELD,
    SURVEY_RESPONSES_SCHEMA,
    SYSTEM_FIELDS,
    generate_schema,
)


# -- generate_schema unit tests --------------------------------------
class TestGenerateSchema:
    """Verify the schema generation function."""

    def test_maps_str_to_string(self):
        """Python str fields become BigQuery STRING columns."""

        class StrModel(BaseModel):
            name: str

        schema = generate_schema(StrModel)
        assert len(schema) == 1
        assert schema[0].name == "name"
        assert schema[0].field_type == "STRING"

    def test_maps_int_to_integer(self):
        """Python int fields become BigQuery INTEGER columns."""

        class IntModel(BaseModel):
            count: int

        schema = generate_schema(IntModel)
        assert schema[0].field_type == "INTEGER"

    def test_required_fields_are_required(self):
        """Required Pydantic fields produce REQUIRED BQ columns."""

        class RequiredModel(BaseModel):
            value: str

        schema = generate_schema(RequiredModel)
        assert schema[0].mode == "REQUIRED"

    def test_optional_fields_are_nullable(self):
        """Optional Pydantic fields produce NULLABLE BQ columns."""

        class OptionalModel(BaseModel):
            value: str = "default"

        schema = generate_schema(OptionalModel)
        assert schema[0].mode == "NULLABLE"

    def test_union_none_fields_are_nullable(self):
        """Fields typed as str | None produce NULLABLE BQ columns."""

        class UnionModel(BaseModel):
            value: str | None = None

        schema = generate_schema(UnionModel)
        assert schema[0].field_type == "STRING"
        assert schema[0].mode == "NULLABLE"

    def test_union_int_none_fields_are_nullable(self):
        """Fields typed as int | None produce NULLABLE INTEGER columns."""

        class UnionIntModel(BaseModel):
            count: int | None = None

        schema = generate_schema(UnionIntModel)
        assert schema[0].field_type == "INTEGER"
        assert schema[0].mode == "NULLABLE"

    def test_column_names_are_lowercased(self):
        """Field names are lowercased in the generated schema."""

        class MixedCaseModel(BaseModel):
            PA1: str | None = None
            response_id: str

        schema = generate_schema(MixedCaseModel)
        names = [f.name for f in schema]
        assert names == ["pa1", "response_id"]

    def test_descriptions_carried_through(self):
        """Pydantic Field descriptions become BQ column descriptions."""

        class DescModel(BaseModel):
            score: int = Field(..., description="Test score out of 100")

        schema = generate_schema(DescModel)
        assert schema[0].description == "Test score out of 100"

    def test_missing_description_defaults_to_empty(self):
        """Fields without descriptions get empty string."""

        class NoDescModel(BaseModel):
            value: int

        schema = generate_schema(NoDescModel)
        assert schema[0].description == ""

    def test_system_fields_appended(self):
        """System fields are added after model fields."""
        from google.cloud.bigquery import SchemaField

        class TinyModel(BaseModel):
            name: str

        system = [
            SchemaField("_created_at", "TIMESTAMP", mode="REQUIRED"),
        ]
        schema = generate_schema(TinyModel, system_fields=system)

        assert len(schema) == 2
        assert schema[0].name == "name"
        assert schema[1].name == "_created_at"

    def test_rejects_unmapped_type(self):
        """Unknown Python types raise ValueError with guidance."""

        class BadModel(BaseModel):
            data: bytes

        with pytest.raises(ValueError, match="No BigQuery type mapping"):
            generate_schema(BadModel)

    def test_field_order_matches_model(self):
        """Generated fields preserve the model's declaration order."""

        class OrderedModel(BaseModel):
            Alpha: str
            Beta: int
            Gamma: str

        schema = generate_schema(OrderedModel)
        names = [f.name for f in schema]
        assert names == ["alpha", "beta", "gamma"]


# -- Generated schema validation -------------------------------------
class TestSurveyResponsesSchema:
    """Verify the generated survey_responses schema is well-formed."""

    def test_schema_is_not_empty(self):
        assert len(SURVEY_RESPONSES_SCHEMA) > 0

    def test_no_duplicate_field_names(self):
        names = [f.name for f in SURVEY_RESPONSES_SCHEMA]
        assert len(names) == len(set(names)), (
            f"Duplicate field names in schema: {names}"
        )

    def test_all_column_names_are_lowercase(self):
        """Every column name in the schema must be lowercase."""
        for field in SURVEY_RESPONSES_SCHEMA:
            assert field.name == field.name.lower(), (
                f"Column '{field.name}' is not lowercase"
            )

    def test_partition_field_exists_in_schema(self):
        column_names = {f.name for f in SURVEY_RESPONSES_SCHEMA}
        assert SURVEY_RESPONSES_PARTITION_FIELD in column_names

    def test_cluster_fields_exist_in_schema(self):
        column_names = {f.name for f in SURVEY_RESPONSES_SCHEMA}
        for field in SURVEY_RESPONSES_CLUSTER_FIELDS:
            assert field in column_names

    def test_partition_field_is_timestamp(self):
        """Partitioning by DAY requires a TIMESTAMP or DATE field."""
        field_map = {f.name: f for f in SURVEY_RESPONSES_SCHEMA}
        part_field = field_map[SURVEY_RESPONSES_PARTITION_FIELD]
        assert part_field.field_type in ("TIMESTAMP", "DATE")

    def test_columns_set_matches_schema(self):
        """The convenience set must match the schema field names."""
        schema_names = {f.name for f in SURVEY_RESPONSES_SCHEMA}
        assert SURVEY_RESPONSES_COLUMNS == schema_names

    def test_column_count_is_model_plus_system(self):
        """Total columns = WebServicePayload fields + system fields."""
        expected = len(WebServicePayload.model_fields) + len(SYSTEM_FIELDS)
        assert len(SURVEY_RESPONSES_SCHEMA) == expected

    def test_system_columns_present(self):
        """System columns (_created_at, _processed) must be in schema."""
        column_names = {f.name for f in SURVEY_RESPONSES_SCHEMA}
        for sys_field in SYSTEM_FIELDS:
            assert sys_field.name in column_names

    def test_system_columns_have_underscore_prefix(self):
        """System columns must start with underscore."""
        for sys_field in SYSTEM_FIELDS:
            assert sys_field.name.startswith("_"), (
                f"System field '{sys_field.name}' missing underscore prefix"
            )

    def test_only_identifiers_are_required(self):
        """Only response_id and survey_id should be REQUIRED
        among the model-derived fields (not system fields).
        """
        system_names = {f.name for f in SYSTEM_FIELDS}
        required_model_fields = [
            f.name
            for f in SURVEY_RESPONSES_SCHEMA
            if f.mode == "REQUIRED" and f.name not in system_names
        ]
        assert sorted(required_model_fields) == [
            "response_id",
            "survey_id",
        ]

    def test_age_is_only_integer_column(self):
        """Only the 'age' column should be INTEGER; rest are STRING
        (plus system TIMESTAMP and BOOLEAN).
        """
        field_map = {f.name: f for f in SURVEY_RESPONSES_SCHEMA}
        integer_fields = [
            name for name, f in field_map.items() if f.field_type == "INTEGER"
        ]
        assert integer_fields == ["age"], (
            f"Expected only 'age' as INTEGER, got: {integer_fields}"
        )


# -- Schema-to-code consistency tests --------------------------------
# -- Schema-to-code consistency tests --------------------------------
class TestInsertRowMatchesSchema:
    """Verify that gcp_utils._build_insert_row produces a row dict
    that exactly matches the BigQuery schema defined in bq_schemas.py.

    These tests call _build_insert_row() directly because it is a
    pure function: no I/O, no BigQuery client, no mocking required.
    The transport layer (Storage Write API) is an I/O concern and
    belongs in integration tests, not unit tests.
    """

    @pytest.fixture
    def sample_payload(self) -> WebServicePayload:
        """Build a valid WebServicePayload for insert testing."""
        return WebServicePayload(
            response_id="R_test123",
            survey_id="SV_test456",
            consent="Yes",
            prolific_pid="test_pid_abc",
            age_flag="Yes",
            fte_flag="Yes",
            location_flag="Yes",
            language_flag="Yes",
            phone="8777804236",
            timezone="US/Central",
            selected_date="12/26/2025",
            age=30,
            ethnicity="Asian",
            gender_identity="Non-binary",
            job_tenure="3 to 5 years",
            education_level="Bachelor's degree",
            remote_flag="Yes",
            PA1="Always",
            PA2="Quite often",
            PA3="Quite often",
            PA4="Always",
            PA5="Quite often",
            NA1="Some of the time",
            NA2="Never",
            NA3="Rather infrequently",
            NA4="Some of the time",
            NA5="Rather infrequently",
            BR1="Disagree",
            BR2="Agree",
            BR3="Agree",
            BR4="Strongly disagree",
            BR5="Agree",
            VIO1="Strongly agree",
            VIO2="Strongly agree",
            VIO3="Neither agree nor disagree",
            VIO4="Disagree",
            JS1="Agree",
        )

    @pytest.fixture
    def partial_payload(self) -> WebServicePayload:
        """Build a partial payload (failed screening)."""
        return WebServicePayload(
            response_id="R_partial_001",
            survey_id="SV_test456",
            consent="No",
            age_flag="No",
        )

    def test_insert_row_keys_match_schema(self, sample_payload):
        """The keys in the insert row must exactly match the schema."""
        from shared.utils.gcp_utils import _build_insert_row

        row = _build_insert_row(sample_payload)
        row_keys = set(row.keys())

        assert row_keys == SURVEY_RESPONSES_COLUMNS, (
            f"Insert row keys do not match schema.\n"
            f"  In row but not schema: "
            f"{row_keys - SURVEY_RESPONSES_COLUMNS}\n"
            f"  In schema but not row: "
            f"{SURVEY_RESPONSES_COLUMNS - row_keys}"
        )

    def test_insert_row_keys_are_lowercase(self, sample_payload):
        """All keys in the insert row must be lowercase."""
        from shared.utils.gcp_utils import _build_insert_row

        row = _build_insert_row(sample_payload)

        for key in row:
            assert key == key.lower(), f"Row key '{key}' is not lowercase"

    def test_insert_row_types_are_serializable(self, sample_payload):
        """All values in the insert row must be JSON-serializable."""
        import json

        from shared.utils.gcp_utils import _build_insert_row

        row = _build_insert_row(sample_payload)

        try:
            json.dumps(row)
        except TypeError as e:
            pytest.fail(f"Insert row contains non-serializable value: {e}")

    def test_partial_payload_insert_keys_match_schema(self, partial_payload):
        """Partial payloads (failed screening) must also match schema."""
        from shared.utils.gcp_utils import _build_insert_row

        row = _build_insert_row(partial_payload)
        row_keys = set(row.keys())

        assert row_keys == SURVEY_RESPONSES_COLUMNS, (
            f"Insert row keys do not match schema.\n"
            f"  In row but not schema: "
            f"{row_keys - SURVEY_RESPONSES_COLUMNS}\n"
            f"  In schema but not row: "
            f"{SURVEY_RESPONSES_COLUMNS - row_keys}"
        )
