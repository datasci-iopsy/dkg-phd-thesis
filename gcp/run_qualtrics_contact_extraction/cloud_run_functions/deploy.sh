#!/bin/bash

sa_name="dkg-cloud-funs"
sa_address=$(gcloud iam service-accounts list \
    --filter="displayName~'$sa_name'" \
    --format="value(email)")
# echo $sa_name
# echo $sa_address

if [ -z "$sa_address" ]; then
    echo "Service account not found!"
    exit 1
fi

# * NOTE: function names can use underscores but the respective url will convert to dashes
fun_name="run_qualtrics_contact_extraction"
region="us-east4"
project_id=$(gcloud config get project)

# * to see list of runtimes RUN: gcloud functions runtimes list
runtime="python311"
entry_point="gspread_handler"
memory="512Mi"
cpu=1
min_instances=1
timeout="300s"
concurrency=80

printf "Note: The service account %s represents the identity of the \
running function %s, and determines what permissions the function has.\n\n" "$sa_address" "$fun_name"

gcloud functions deploy $fun_name \
    --region=$region \
    --project=$project_id \
    --service-account=$sa_address \
    --region=$region \
    --runtime=$runtime \
    --entry-point=$entry_point \
    --memory=$memory \
    --cpu=$cpu \
    --min-instances=$min_instances \
    --timeout=$timeout \
    --concurrency=$concurrency \
    --gen2 \
    --trigger-http \
    --no-allow-unauthenticated

# # # !!! to delete cloud run function RUN:
# # gcloud functions delete run-qualtrics-contact-pipeline --region=us-east4 --gen2

# # # !!! to delete entire artifact repository RUN:
# # gcloud artifacts repositories delete gcf-artifacts --location=us-east4
