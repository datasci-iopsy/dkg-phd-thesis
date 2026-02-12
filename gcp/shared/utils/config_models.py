"""
Pydantic configuration models for Cloud Run function settings.

Defines the validated schema for all YAML configuration files.
Each model maps 1:1 to a top-level key in the merged config.
"""

from pydantic import BaseModel, Field


class GCPConfig(BaseModel):
    """Google Cloud Platform project settings.

    GCP uses two distinct geographic concepts:
        - location: Multi-region for BigQuery datasets (e.g., "US").
        - region: Specific region for compute resources like
          Cloud Run functions (e.g., "us-east4").
    """

    project_id: str = Field(
        ..., description="GCP project ID (e.g., 'dkg-phd-thesis')"
    )
    location: str = Field(
        ..., description="Multi-region for BigQuery (e.g., 'US')"
    )
    region: str = Field(
        ..., description="Compute region for Cloud Run (e.g., 'us-east4')"
    )


class SecretManagerConfig(BaseModel):
    """Secret Manager resource references.

    These map logical names to their Secret Manager IDs.
    Actual secret values are injected as environment variables
    at deploy time via --set-secrets, not read from here.
    """

    qualtrics_api_key: str = Field(
        ..., description="Secret Manager ID for Qualtrics API key"
    )
    qualtrics_api_key_version_id: str = "latest"
    qualtrics_webhook: str = Field(
        ..., description="Secret Manager ID for webhook HMAC secret"
    )
    qualtrics_webhook_version_id: str = "latest"


class TablesConfig(BaseModel):
    """BigQuery table name references.

    Groups all table names under a single config key so that
    dataset-level settings (dataset_id) stay separate from
    table-level references. Add new tables here as the pipeline
    grows.

    Naming convention:
        <purpose>_<stage>
        - purpose: intake (survey 0) or followup (surveys 1-3)
        - stage: raw (direct from Qualtrics) or clean (processed)
    """

    intake_raw: str = Field(
        ..., description="Raw intake survey responses (survey 0)"
    )
    intake_clean: str = Field(..., description="Cleaned/processed intake data")
    followup_raw: str = Field(
        ..., description="Raw follow-up responses (surveys 1-3, same table)"
    )
    followup_clean: str = Field(
        ..., description="Cleaned/processed follow-up data"
    )


class BigQueryConfig(BaseModel):
    """BigQuery dataset and table configuration.

    Separates connection-level config (dataset_id) from table
    references (tables.*) for clarity as the number of tables
    grows.
    """

    dataset_id: str = Field(..., description="BigQuery dataset name")
    tables: TablesConfig


class QualtricsConfig(BaseModel):
    """Qualtrics API connection settings."""

    base_url: str = Field(
        ...,
        description="Qualtrics REST API base (e.g., https://yul1.qualtrics.com/API/v3)",
    )
    survey_base_url: str = Field(
        ...,
        description="Qualtrics survey URL base for follow-up links",
    )


class AppConfig(BaseModel):
    """Top-level application configuration.

    Composed from all YAML files in the function's configs/ directory.
    Each field corresponds to a top-level YAML key.

    Usage after loading:
        config.gcp.project_id
        config.gcp.location         # "US" (for BigQuery)
        config.gcp.region           # "us-east4" (for Cloud Run)
        config.bq.dataset_id
        config.bq.tables.intake_raw
        config.qualtrics.base_url
    """

    gcp: GCPConfig
    secret_manager: SecretManagerConfig
    bq: BigQueryConfig
    qualtrics: QualtricsConfig
