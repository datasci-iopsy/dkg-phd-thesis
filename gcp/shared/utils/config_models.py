"""
Pydantic configuration models for Cloud Run function settings.

Defines the validated schema for all YAML configuration files.
Each model maps 1:1 to a top-level key in the merged config.
"""

from __future__ import annotations

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

    Currently unused -- the API Gateway handles authentication
    for inbound webhooks and the Web Service task sends complete
    payloads, eliminating the need for Qualtrics API calls.
    Retained so secrets can be re-added by including a
    secret_manager block in the YAML config.
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
    scheduled_followups: str | None = Field(
        default=None,
        description="Follow-up SMS scheduling records (operational table)",
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


class PubSubConfig(BaseModel):
    """Pub/Sub topic references for async message passing.

    Used by functions that publish messages after processing.
    Functions that only receive messages (via Eventarc push
    subscriptions) do not need this config.

    topic_id: Used by run-qualtrics-scheduling to publish
        intake-processed messages.
    followup_topic_id: Used by run-intake-confirmation to
        publish follow-up scheduling messages.
    """

    topic_id: str = Field(
        ..., description="Pub/Sub topic ID (e.g., 'dkg-intake-processed')"
    )
    followup_topic_id: str | None = Field(
        default=None,
        description="Pub/Sub topic ID for follow-up scheduling "
        "(e.g., 'dkg-followup-scheduling')",
    )


class FollowupSurveysConfig(BaseModel):
    """Qualtrics follow-up survey configuration.

    Defines the three follow-up surveys (one per daily time slot)
    and the SMS template used when scheduling messages via Twilio.

    Each survey_id corresponds to a fixed time slot:
        survey_ids[0] → 9:00 AM
        survey_ids[1] → 1:00 PM
        survey_ids[2] → 5:00 PM
    """

    survey_base_url: str = Field(
        ..., description="Base URL for Qualtrics survey links"
    )
    survey_ids: list[str] = Field(
        ...,
        min_length=3,
        max_length=3,
        description="Three Qualtrics survey IDs, one per time slot",
    )
    sms_template: str = Field(
        default=(
            "Hello, this is Demetrius K. Green. It is time for your "
            "{time} follow-up survey for the research study. Please "
            "complete it within 1 hour for your response to be valid: "
            "{url}"
        ),
        description="SMS body template with {time} and {url} placeholders",
    )


class AppConfig(BaseModel):
    """Top-level application configuration.

    Composed from all YAML files in the function's configs/ directory.
    Each field corresponds to a top-level YAML key. Optional fields
    allow functions to include only the config sections they need.

    Usage after loading:
        config.gcp.project_id
        config.gcp.location         # "US" (for BigQuery)
        config.gcp.region           # "us-east4" (for Cloud Run)
        config.bq.dataset_id
        config.bq.tables.intake_raw
        config.qualtrics.base_url   # only if qualtrics config present
        config.pubsub.topic_id      # only if pubsub config present
        config.followup_surveys     # only if followup config present
    """

    gcp: GCPConfig
    secret_manager: SecretManagerConfig | None = None
    bq: BigQueryConfig
    qualtrics: QualtricsConfig | None = None
    pubsub: PubSubConfig | None = None
    followup_surveys: FollowupSurveysConfig | None = None
