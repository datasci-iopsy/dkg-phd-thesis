#!/usr/bin/env bash

gcp_region=$(gcloud config get compute/region)
project_id="$(gcloud config get core/project)"
dataset_id="qualtrics_db"

# ! TO DELETE RUN THE FOLLOWING COMMAND:
bq rm -f "${project_id}:${dataset_id}.raw_demo_control_vars"
bq rm -f "${project_id}:${dataset_id}.raw_study_vars"
