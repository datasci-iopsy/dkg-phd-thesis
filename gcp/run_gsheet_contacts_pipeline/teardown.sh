#!/usr/bin/env bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR" # ! <-- THIS IS CRITICAL

fun_name="run-gsheet-contacts-pipeline"
region="us-east4"
project_id=$(gcloud config get project)

job_name="${fun_name}-job"
cron_sched="*/15 * * * *"
fun_uri=$(gcloud functions describe $fun_name \
    --region=$region \
    --format="value(serviceConfig.uri)")

# !!! to delete cloud run function RUN:
gcloud functions delete $fun_name --region=$region --gen2

# # !!! to delete entire artifact repository RUN:
# gcloud artifacts repositories delete gcf-artifacts --location=$region

# !!! to delete cloud scheduler job RUN:
gcloud scheduler jobs delete $job_name --location=$region