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

fun_name="run-qualtrics-contact-pipeline"
region="us-east4"
project_id=$(gcloud config get project)
# * gcloud functions runtimes list
runtime="python311"
entry_point="qualtrics_receiver"
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

# gcloud auth print-identity-token \
#     --audiences=https://run-qualtrics-contact-pipeline-uep2ub7uja-uk.a.run.app \
#     --impersonate-service-account=dkg-cloud-funs@dkg-phd-thesis.iam.gserviceaccount.com

# # # ! TO DELETE RUN:
# # gcloud functions delete run_contact_pipeline --region=us-east4 --gen2
# # gcloud artifacts repositories delete gcf-artifacts
