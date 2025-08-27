#!/usr/bin/env bash

set -euo pipefail

# echo $BASH_VERSION

# Configuration
declare DATASET="qualtrics_db"
declare -A TABLES=(
    ["raw_demo_control_vars"]="schemas/raw_demo_control_vars.json"
    ["raw_study_vars"]="schemas/raw_study_vars.json"
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
            bq show --schema --format=prettyjson ${PROJECT_ID}:${DATASET}.${table}
        else
            log_error "Failed to create table $table: $output"
        fi
    fi
done

log_success "All operations completed"
