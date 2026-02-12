"""BigQuery table schema definitions.

Generates the survey_responses schema from the WebServicePayload
Pydantic model at import time. This ensures a single source of
truth for field names, types, and descriptions -- when the survey
changes, update the Pydantic model in qualtrics.py and the
BigQuery schema follows automatically.

Column naming rules:
    - All column names are lowercased (PA1 -> pa1).
    - System columns are prefixed with underscore (_created_at).

The only manually defined fields are system columns (_created_at,
_processed) that exist in BigQuery but not on the payload model.

When adding a new table:
    1. Define a Pydantic model for the payload.
    2. Call generate_schema() with that model and any system fields.
    3. Add the table name to the function's config YAML.
    4. Add a provisioning entry in manage_infra.py.
    5. Write the corresponding insert function in gcp_utils.py.
"""

import types
from typing import get_args, get_origin

from google.cloud.bigquery import SchemaField
from pydantic import BaseModel

# -- Python type -> BigQuery type ------------------------------------
# Covers the types used by WebServicePayload. Extend this mapping
# if future models introduce additional types (e.g., float -> FLOAT,
# bool -> BOOLEAN).
_PYTHON_TO_BQ: dict[type, str] = {
    str: "STRING",
    int: "INTEGER",
    float: "FLOAT",
    bool: "BOOLEAN",
}

# -- System columns (not on the payload model) -----------------------
# These are added to the generated schema after the model fields.
# Define them here because they represent pipeline concerns (when
# the row was written, whether it has been processed) rather than
# survey data. Prefixed with underscore to distinguish from
# survey-derived columns.
SYSTEM_FIELDS: list[SchemaField] = [
    SchemaField(
        "_created_at",
        "TIMESTAMP",
        mode="REQUIRED",
        description="UTC timestamp when this row was inserted",
    ),
    SchemaField(
        "_processed",
        "BOOLEAN",
        mode="REQUIRED",
        description="Whether downstream processing has completed",
    ),
]


def _unwrap_optional(annotation: type) -> type:
    """Extract the base type from an Optional/Union annotation.

    Handles both typing.Union (Optional[str]) and the Python 3.10+
    union syntax (str | None). Returns the non-None type if the
    annotation is a union with exactly one non-None member,
    otherwise returns the annotation unchanged.
    """
    origin = get_origin(annotation)

    # str | None uses types.UnionType in Python 3.10+
    if origin is types.UnionType:
        args = get_args(annotation)
        non_none = [a for a in args if a is not type(None)]
        if len(non_none) == 1:
            return non_none[0]

    return annotation


def generate_schema(
    model: type[BaseModel],
    system_fields: list[SchemaField] | None = None,
) -> list[SchemaField]:
    """Generate a BigQuery schema from a Pydantic model.

    Iterates over the model's fields, maps each Python type
    annotation to a BigQuery type, and builds a list of
    SchemaField objects. System fields (columns that exist in
    BigQuery but not on the model) are appended at the end.

    Column names are lowercased (e.g., PA1 -> pa1) for BigQuery
    consistency. Optional fields (with defaults) become NULLABLE;
    required fields (no default) become REQUIRED.

    Args:
        model: A Pydantic BaseModel class to introspect.
        system_fields: Additional SchemaField objects to append
            after the model-derived fields (e.g., _created_at).

    Returns:
        Complete list of SchemaField objects for table creation.

    Raises:
        ValueError: If a field's Python type has no BigQuery
            mapping in _PYTHON_TO_BQ.
    """
    fields: list[SchemaField] = []

    for name, field_info in model.model_fields.items():
        python_type = _unwrap_optional(field_info.annotation)
        bq_type = _PYTHON_TO_BQ.get(python_type)

        if bq_type is None:
            raise ValueError(
                f"No BigQuery type mapping for field '{name}' "
                f"with Python type '{python_type}'. Add an entry "
                f"to _PYTHON_TO_BQ in bq_schemas.py."
            )

        mode = "REQUIRED" if field_info.is_required() else "NULLABLE"
        description = field_info.description or ""

        fields.append(
            SchemaField(
                name.lower(), bq_type, mode=mode, description=description
            )
        )

    if system_fields:
        fields.extend(system_fields)

    return fields


# -- Generate the survey_responses schema ----------------------------
# Import here (not at module top) to keep the generic generate_schema
# function free of model-specific dependencies. This import works
# because the function directory is on sys.path at runtime
# (functions-framework), in tests (conftest.py), and in CLI tools
# (manage_infra.py adds it explicitly).
from models.qualtrics import WebServicePayload  # noqa: E402

SURVEY_RESPONSES_SCHEMA: list[SchemaField] = generate_schema(
    WebServicePayload,
    system_fields=SYSTEM_FIELDS,
)

# Partitioning and clustering configuration for survey_responses.
SURVEY_RESPONSES_PARTITION_FIELD: str = "_created_at"
SURVEY_RESPONSES_CLUSTER_FIELDS: list[str] = ["survey_id"]

# Column name set for consistency checking in tests.
SURVEY_RESPONSES_COLUMNS: set[str] = {
    field.name for field in SURVEY_RESPONSES_SCHEMA
}
