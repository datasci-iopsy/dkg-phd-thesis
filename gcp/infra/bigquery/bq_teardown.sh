#!/usr/bin/env bash

gcp_region=$(gcloud config get compute/region)
project_id="$(gcloud config get core/project)"
dataset_id="qualtrics_db"

# ! to delete dataset and tables recursively RUN:
bq rm -r -f -d ${project_id}:${dataset_id}
