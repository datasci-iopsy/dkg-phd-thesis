#!/usr/bin/env bash

gcp_region=$(gcloud config get compute/region)
project_id="$(gcloud config get core/project)"
dataset_id="qualtrics_raw_db"

# ! TO DELETE RUN THE FOLLOWING COMMAND:
bq rm -r -f -d ${project_id}:${dataset_id}

gcp_region=$(gcloud config get compute/region)
project_id="$(gcloud config get core/project)"
dataset_id="qualtrics_clean_db"

# ! TO DELETE RUN THE FOLLOWING COMMAND:
bq rm -r -f -d ${project_id}:${dataset_id}
