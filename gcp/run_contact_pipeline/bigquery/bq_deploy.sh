#!/bin/bash

# export GCP_REGION="us-east4"
gcp_region=$(gcloud config get compute/region)
dataset_description="Dataset comprising all tables for PhD thesis project."
project_id="$(gcloud config get project)"
dataset_id="dkg_phd_thesis_db"

table_description="Table comprising raw contact data."
table_id="raw_contacts"
schema_path="schemas/raw_contacts.json"

# # ! TO DELETE RUN COMMAND BELOW:
# bq rm -r -f -d ${project_id}:${dataset_id}

# * create a dataset in BigQuery
bq mk --location=${gcp_region} \
    --dataset \
    --description="${dataset_description}" \
    ${project_id}:${dataset_id}

# * create a table in BigQuery
bq mk \
    --table \
    --description="${table_description}" \
    ${project_id}:${dataset_id}.${table_id} \
    ${schema_path}

bq show \
    --schema \
    --format=prettyjson \
    ${project_id}:${dataset_id}.${table_id}

bq show --schema --format=prettyjson ${dataset_id}.${table_id}