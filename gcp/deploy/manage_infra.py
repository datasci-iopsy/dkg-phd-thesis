"""BigQuery infrastructure provisioning.

Creates datasets and tables with validated schemas. Idempotent --
safe to run repeatedly. Reads table/dataset names from the same
YAML config files the application uses at runtime, so there is
no drift between what the infra script creates and what the
function writes to.

Usage:
    python manage_infra.py status
    python manage_infra.py setup
    python manage_infra.py teardown
    python manage_infra.py teardown --force
    python manage_infra.py --help

Lives alongside manage_functions.py in gcp/deploy/.
"""

import argparse
import sys
from pathlib import Path

import yaml
from google.api_core.exceptions import Conflict, NotFound
from google.cloud import bigquery

# -- Path resolution -------------------------------------------------
DEPLOY_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = DEPLOY_DIR.parents[1]
FUNCTIONS_BASE = PROJECT_ROOT / "gcp" / "cloud_run_functions"

# Load GCP config from the qualtrics scheduling function's configs.
# This is the same file the function reads at runtime.
_gcp_config_path = (
    FUNCTIONS_BASE / "run_qualtrics_scheduling" / "configs" / "gcp_config.yaml"
)
_gcp_config = yaml.safe_load(_gcp_config_path.read_text())

PROJECT_ID: str = _gcp_config["gcp"]["project_id"]
LOCATION: str = _gcp_config["gcp"]["location"]
DATASET_ID: str = _gcp_config["bq"]["dataset_id"]
TABLES: dict[str, str] = _gcp_config["bq"]["tables"]

# Add gcp/ to path so 'shared.utils...' imports work.
# Add the function directory so 'models...' imports resolve
# (bq_schemas.py imports WebServicePayload to generate the schema).
_gcp_dir = str(PROJECT_ROOT / "gcp")
if _gcp_dir not in sys.path:
    sys.path.insert(0, _gcp_dir)

_fn_dir = str(FUNCTIONS_BASE / "run_qualtrics_scheduling")
if _fn_dir not in sys.path:
    sys.path.insert(0, _fn_dir)

from shared.utils.bq_schemas import (
    SURVEY_RESPONSES_CLUSTER_FIELDS,
    SURVEY_RESPONSES_PARTITION_FIELD,
    SURVEY_RESPONSES_SCHEMA,
)

# -- Table registry --------------------------------------------------
# Maps config keys to their schema + partition/cluster settings.
# Only tables with defined schemas are provisioned by 'setup'.
# Tables not yet in this registry appear in 'status' as
# "not provisioned" and are skipped during setup.
#
# When a new table's schema is ready, add it here.
TABLE_REGISTRY: dict[str, dict] = {
    "intake_raw": {
        "schema": SURVEY_RESPONSES_SCHEMA,
        "partition_field": SURVEY_RESPONSES_PARTITION_FIELD,
        "cluster_fields": SURVEY_RESPONSES_CLUSTER_FIELDS,
        "description": (
            "Raw intake survey responses (survey 0) from the "
            "Qualtrics Web Service task. Each row is one completed "
            "response with explicit typed columns."
        ),
    },
    # -- Future tables -----------------------------------------------
    # "intake_clean": {
    #     "schema": INTAKE_CLEAN_SCHEMA,
    #     "partition_field": ...,
    #     "cluster_fields": ...,
    #     "description": "...",
    # },
    # "followup_raw": {
    #     "schema": FOLLOWUP_RESPONSES_SCHEMA,
    #     "partition_field": ...,
    #     "cluster_fields": ...,
    #     "description": "...",
    # },
    # "followup_clean": { ... },
}


# -- Helpers ---------------------------------------------------------
def get_client() -> bigquery.Client:
    """Create a BigQuery client for the configured project."""
    return bigquery.Client(project=PROJECT_ID)


def print_banner(action: str) -> None:
    """Print a formatted operation banner."""
    print(f"\n+{'=' * 50}+")
    print(f"|  {action:<48}|")
    print(f"|  Project:   {PROJECT_ID:<38}|")
    print(f"|  Location:  {LOCATION:<38}|")
    print(f"|  Dataset:   {DATASET_ID:<38}|")
    print(f"+{'=' * 50}+")


# -- Dataset operations ----------------------------------------------
def dataset_exists(client: bigquery.Client) -> bool:
    """Check whether the configured dataset exists."""
    dataset_ref = f"{PROJECT_ID}.{DATASET_ID}"
    try:
        client.get_dataset(dataset_ref)
        return True
    except NotFound:
        return False


def create_dataset(client: bigquery.Client) -> None:
    """Create the dataset if it does not exist."""
    dataset_ref = f"{PROJECT_ID}.{DATASET_ID}"

    if dataset_exists(client):
        print(f"  Dataset '{DATASET_ID}' already exists -- skipping.")
        return

    dataset = bigquery.Dataset(dataset_ref)
    dataset.location = LOCATION

    try:
        client.create_dataset(dataset)
        print(f"  Created dataset '{DATASET_ID}' in {LOCATION}.")
    except Conflict:
        # Race condition guard -- another process created it
        print(f"  Dataset '{DATASET_ID}' already exists -- skipping.")


# -- Table operations ------------------------------------------------
def table_exists(client: bigquery.Client, table_id: str) -> bool:
    """Check whether a specific table exists in the dataset."""
    full_id = f"{PROJECT_ID}.{DATASET_ID}.{table_id}"
    try:
        client.get_table(full_id)
        return True
    except NotFound:
        return False


def create_table(
    client: bigquery.Client,
    table_id: str,
    schema: list[bigquery.SchemaField],
    partition_field: str | None = None,
    cluster_fields: list[str] | None = None,
    description: str = "",
) -> None:
    """Create a table with the given schema if it does not exist.

    Args:
        client: BigQuery client.
        table_id: Table name (without project/dataset prefix).
        schema: List of SchemaField definitions.
        partition_field: Column name for time-based partitioning.
        cluster_fields: Column names for clustering.
        description: Human-readable table description.
    """
    full_id = f"{PROJECT_ID}.{DATASET_ID}.{table_id}"

    if table_exists(client, table_id):
        print(f"  Table '{table_id}' already exists -- skipping.")
        return

    table = bigquery.Table(full_id, schema=schema)
    table.description = description

    if partition_field:
        table.time_partitioning = bigquery.TimePartitioning(
            type_=bigquery.TimePartitioningType.DAY,
            field=partition_field,
        )

    if cluster_fields:
        table.clustering_fields = cluster_fields

    try:
        client.create_table(table)
        parts = []
        if partition_field:
            parts.append(f"partitioned by {partition_field}")
        if cluster_fields:
            parts.append(f"clustered by {', '.join(cluster_fields)}")
        detail = f" ({', '.join(parts)})" if parts else ""
        print(f"  Created table '{table_id}'{detail}.")
    except Conflict:
        print(f"  Table '{table_id}' already exists -- skipping.")


# -- Status ----------------------------------------------------------
def print_schema(client: bigquery.Client, table_id: str) -> None:
    """Print the schema of an existing table."""
    full_id = f"{PROJECT_ID}.{DATASET_ID}.{table_id}"
    try:
        table = client.get_table(full_id)
        print(f"\n  Schema for '{table_id}':")
        for field in table.schema:
            print(f"    {field.name:<25} {field.field_type:<12} {field.mode}")
        if table.time_partitioning:
            print(f"    -- partitioned by: {table.time_partitioning.field}")
        if table.clustering_fields:
            print(
                f"    -- clustered by:   {', '.join(table.clustering_fields)}"
            )
        print(f"    -- rows: {table.num_rows}")
    except NotFound:
        print(f"\n  Table '{table_id}' does not exist.")


# -- Subcommand handlers ---------------------------------------------
def handle_status(args: argparse.Namespace) -> None:
    """Show the current state of BigQuery infrastructure."""
    print_banner("Infrastructure status")
    client = get_client()

    if not dataset_exists(client):
        print(f"\n  Dataset '{DATASET_ID}' does not exist.")
        print("  Run 'setup' to create it.\n")
        return

    print(f"\n  Dataset '{DATASET_ID}' exists.")

    for config_key, bq_table_name in TABLES.items():
        has_schema = config_key in TABLE_REGISTRY
        tag = "" if has_schema else " (no schema defined yet)"
        print(f"\n  --- {config_key}{tag} ---")
        print_schema(client, bq_table_name)

    print()


def handle_setup(args: argparse.Namespace) -> None:
    """Provision all BigQuery resources with defined schemas."""
    print_banner("Provisioning infrastructure")
    client = get_client()

    print(f"\n  --- Dataset ---")
    create_dataset(client)

    print(f"\n  --- Tables ---")
    for config_key, bq_table_name in TABLES.items():
        if config_key not in TABLE_REGISTRY:
            print(
                f"  Skipping '{config_key}' ({bq_table_name}) "
                f"-- no schema defined yet."
            )
            continue

        registry = TABLE_REGISTRY[config_key]
        create_table(
            client,
            table_id=bq_table_name,
            schema=registry["schema"],
            partition_field=registry.get("partition_field"),
            cluster_fields=registry.get("cluster_fields"),
            description=registry.get("description", ""),
        )

    print(f"\n  Setup complete.\n")


def handle_teardown(args: argparse.Namespace) -> None:
    """Delete BigQuery tables (dataset is preserved).

    Deletes all tables listed in config. The dataset itself is
    kept because other tables or future functions may use it.
    Use --force to skip the confirmation prompt.
    """
    print_banner("Tearing down tables")
    client = get_client()

    if not dataset_exists(client):
        print(f"\n  Dataset '{DATASET_ID}' does not exist -- nothing to do.\n")
        return

    existing = [
        (key, name)
        for key, name in TABLES.items()
        if table_exists(client, name)
    ]

    if not existing:
        print("\n  No tables found -- nothing to delete.\n")
        return

    if not args.force:
        print("\n  This will permanently delete the following tables:")
        for key, name in existing:
            print(f"    - {DATASET_ID}.{name} ({key})")
        print()
        response = input("  Type 'yes' to confirm: ")
        if response.strip().lower() != "yes":
            print("\n  Teardown cancelled.\n")
            return

    for key, name in existing:
        full_id = f"{PROJECT_ID}.{DATASET_ID}.{name}"
        client.delete_table(full_id)
        print(f"  Deleted table '{name}' ({key}).")

    print(f"\n  Teardown complete. Dataset '{DATASET_ID}' preserved.\n")


# -- CLI definition --------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="manage_infra",
        description="BigQuery infrastructure provisioning.",
    )
    subparsers = parser.add_subparsers(
        dest="command",
        required=True,
    )

    status_parser = subparsers.add_parser(
        "status",
        help="Show current state of BigQuery resources.",
    )
    status_parser.set_defaults(handler=handle_status)

    setup_parser = subparsers.add_parser(
        "setup",
        help="Create datasets and tables (idempotent).",
    )
    setup_parser.set_defaults(handler=handle_setup)

    teardown_parser = subparsers.add_parser(
        "teardown",
        help="Delete tables (preserves dataset).",
    )
    teardown_parser.add_argument(
        "--force",
        "-f",
        action="store_true",
        help="Skip confirmation prompt.",
    )
    teardown_parser.set_defaults(handler=handle_teardown)

    return parser


# -- Entrypoint ------------------------------------------------------
def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.handler(args)


if __name__ == "__main__":
    main()
