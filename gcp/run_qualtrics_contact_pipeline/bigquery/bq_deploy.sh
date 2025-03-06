#!/usr/bin/env bash

set -euo pipefail

echo $BASH_VERSION

# Configuration
declare -a DATASETS=("qualtrics_raw_db" "qualtrics_clean_db")
declare -A TABLES=(
    ["raw_contact_info"]="schemas/raw_contact_info.json"
    ["raw_time_invariant_vars"]="schemas/raw_time_invariant_vars.json"
    ["raw_time_variant_vars"]="schemas/raw_time_variant_vars.json"
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

# Dataset creation with error handling
for dataset in "${DATASETS[@]}"; do
    echo "Creating dataset: $dataset"
    if output=$(bq mk --location="${GCP_REGION}" --dataset "${PROJECT_ID}:${dataset}" 2>&1); then
        log_success "Dataset $dataset created successfully"
    else
        if [[ $output == *"already exists"* ]]; then
            log_warning "Dataset $dataset already exists - skipping"
        else
            log_error "Failed to create dataset $dataset: $output"
        fi
    fi
done

# Table creation with error handling
for table in "${!TABLES[@]}"; do
    schema=${TABLES[$table]}
    echo "Creating table: $table with schema $schema"

    [[ -f "$schema" ]] || log_error "Schema file $schema not found"

    if output=$(bq mk --table "${PROJECT_ID}:qualtrics_clean_db.${table}" "$schema" 2>&1); then
        log_success "Table $table created successfully"
    else
        if [[ $output == *"already exists"* ]]; then
            log_warning "Table $table already exists - skipping"
        else
            log_error "Failed to create table $table: $output"
        fi
    fi

    # Schema display (continues even if table existed)
    if ! bq show --schema --format=prettyjson "${PROJECT_ID}:qualtrics_clean_db.${table}"; then
        log_error "Failed to show schema for $table"
    fi
done

log_success "All operations completed"
