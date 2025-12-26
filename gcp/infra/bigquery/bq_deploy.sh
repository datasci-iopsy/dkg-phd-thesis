#!/usr/bin/env bash

# echo $BASH_VERSION

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
pushd "$SCRIPT_DIR" >/dev/null # ! <-- THIS IS CRITICAL

# Configuration
declare DATASET="qualtrics_db"
declare -A TABLES=(
    ["stg_qualtrics__survey0"]="$SCRIPT_DIR/schemas/stg_qualtrics__survey0.json"
    # ["clean_contact_directory"]="$SCRIPT_DIR/schemas/clean_contact_directory.json"
)

# Enhanced logging functions
log_error() {
    echo -e "\033[31mError: $1\033[0m" >&2
    exit 1
}

log_warning() {
    echo -e "\033[33mWarning: $1\033[0m" >&2
}

log_success() {
    echo -e "\033[32m$1\033[0m"
}

# Get GCP configuration
PROJECT_ID=$(gcloud config get core/project) || log_error "Failed to get project ID"
GCP_REGION=$(gcloud config get compute/region) || log_error "Failed to get region"

echo "Checking if dataset $DATASET exists..."
if bq ls -d | grep -qw "$DATASET"; then
    log_warning "Dataset $DATASET already exists - skipping"
else
    echo "Creating dataset: $DATASET"
    bq mk --location="${GCP_REGION}" --dataset "${PROJECT_ID}:${DATASET}" &&
        log_success "Dataset $DATASET created successfully" ||
        log_error "Failed to create dataset $DATASET"
fi

# Table creation with error handling
for table in "${!TABLES[@]}"; do
    schema=${TABLES[$table]}
    echo "Creating table: $table with schema $schema"

    [[ -f "$schema" ]] || log_error "Schema file $schema not found"

    if output=$(bq mk --table "${PROJECT_ID}:$DATASET.${table}" "$schema" 2>&1); then
        log_success "Table $table created successfully"
        bq show --schema --format=prettyjson ${PROJECT_ID}:${DATASET}.${table}
    else
        if [[ $output == *"already exists"* ]]; then
            log_warning "Table $table already exists - skipping"
            # bq show --schema --format=prettyjson ${PROJECT_ID}:${DATASET}.${table}
        else
            log_error "Failed to create table $table: $output"
        fi
    fi
done

log_success "All operations completed"

popd >/dev/null
