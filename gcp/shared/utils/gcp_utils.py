"""BigQuery data operations for survey response storage."""

import logging
from datetime import UTC, datetime

from google.cloud import bigquery
from google.cloud.exceptions import GoogleCloudError
from models.qualtrics import WebServicePayload
from shared.utils.config_models import AppConfig

logger = logging.getLogger(__name__)


def get_bigquery_client(config: AppConfig) -> bigquery.Client:
    """Initialize a BigQuery client from application config.

    Args:
        config: Validated application configuration.

    Returns:
        Authenticated BigQuery client scoped to the project.
    """
    return bigquery.Client(project=config.gcp.project_id)


def insert_survey_response(
    payload: WebServicePayload,
    table_name: str,
    config: AppConfig,
) -> bool:
    """Insert a survey response into BigQuery via streaming API.

    Writes the full WebServicePayload as explicit typed columns.
    The row structure must match the schema generated from the
    WebServicePayload model in bq_schemas.py -- the two stay in
    sync automatically.

    Column names are lowercased to match the BigQuery schema
    (e.g., PA1 -> pa1). System columns are prefixed with
    underscore (_created_at, _processed).

    The table_name parameter allows the same function to write
    to different tables (e.g., intake_responses vs
    followup_responses) depending on the survey type.

    Args:
        payload: Validated survey response from the Qualtrics
            Web Service task.
        table_name: Target BigQuery table name (e.g.,
            config.bq.tables.intake_raw).
        config: Validated application configuration.

    Returns:
        True if the insert succeeded, False otherwise.
    """
    try:
        client = get_bigquery_client(config)

        full_table_id = (
            f"{config.gcp.project_id}.{config.bq.dataset_id}.{table_name}"
        )

        now = datetime.now(UTC).isoformat()

        # Build the row from the payload. model_dump() gives us all
        # survey fields with the correct names and types. Keys are
        # lowercased to match the BigQuery schema (PA1 -> pa1).
        # System columns use underscore prefix (_created_at).
        row = {k.lower(): v for k, v in payload.model_dump().items()}
        row["_created_at"] = now
        row["_processed"] = False

        table = client.get_table(full_table_id)
        errors = client.insert_rows_json(table, [row])

        if errors:
            logger.error("BigQuery insert errors: %s", errors)
            return False

        logger.info(
            "Successfully inserted response %s into %s",
            payload.response_id,
            full_table_id,
        )
        return True

    except GoogleCloudError as e:
        logger.error("BigQuery error: %s", e, exc_info=True)
        return False
    except Exception as e:
        logger.error(
            "Unexpected error writing to BigQuery: %s", e, exc_info=True
        )
        return False
