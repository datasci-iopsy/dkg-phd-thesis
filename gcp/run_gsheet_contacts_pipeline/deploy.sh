#!/usr/bin/env bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR" # ! <-- THIS IS CRITICAL

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Deploy BigQuery resources
log_message "Deploying BigQuery resources..."
if ! ./bigquery/bq_deploy.sh; then
    log_message "Error: BigQuery deployment failed"
    exit 1
fi

# sa_name="dkg-cloud-funs"
# sa_address=$(gcloud iam service-accounts list \
#     --filter="displayName~'$sa_name'" \
#     --format="value(email)")
# # echo $sa_name
# # echo $sa_address

# if [ -z "$sa_address" ]; then
#     echo "Service account not found!"
#     exit 1
# fi

# # * NOTE: function names can use underscores but the respective url will convert to dashes
# fun_name="run-gsheet-contacts-pipeline"
# region="us-east4"
# project_id=$(gcloud config get project)

# # * to see list of runtimes RUN: gcloud functions runtimes list
# runtime="python311"
# entry_point="stream_raw_contact_directory"
# source="cloud_run_functions"
# memory="512Mi"
# cpu=1
# min_instances=1
# timeout="300s"
# concurrency=80

# printf "Note: The service account %s represents the identity of the \
# running function %s, and determines what permissions the function has.\n\n" "$sa_address" "$fun_name"

# # Deploy Cloud Function
# log_message "Deploying Cloud Function..."

# gcloud functions deploy $fun_name \
#     --region=$region \
#     --project=$project_id \
#     --service-account=$sa_address \
#     --region=$region \
#     --runtime=$runtime \
#     --entry-point=$entry_point \
#     --source=$source \
#     --memory=$memory \
#     --cpu=$cpu \
#     --min-instances=$min_instances \
#     --timeout=$timeout \
#     --concurrency=$concurrency \
#     --gen2 \
#     --trigger-http \
#     --no-allow-unauthenticated

# job_name="${fun_name}-job"
# cron_sched="*/15 * * * *"
# fun_uri=$(gcloud functions describe $fun_name \
#     --region=$region \
#     --format="value(serviceConfig.uri)")

# # # echo "Function URI: $function_uri"

# # Create Scheduler job
# log_message "Creating Scheduler job..."

# gcloud scheduler jobs create http "${job_name}" \
#     --location=$region \
#     --schedule="$cron_sched" \
#     --http-method=POST \
#     --uri=$fun_uri \
#     --oidc-service-account-email=$sa_address \
#     --oidc-token-audience=$fun_uri

# log_message "Deployment completed successfully"