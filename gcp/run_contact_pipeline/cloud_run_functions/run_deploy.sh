#!/bin/bash
#!/bin/bash

project_id="$(gcloud config get project)"
# project_id="$(gcloud info --format='value(config.project)')"
# dataset_id="dkg_phd_thesis_db"
# table_id="raw_contacts"

topic_id="qualtrics-raw-contacts-topic"
# subscription_id="bq-qualtrics-raw-responses-subscription"

# # ! TO DELETE RUN COMMAND BELOW:
# gcloud pubsub topics delete ${topic_id} \
#     --project="${project_id}"

# * create topic
gcloud pubsub topics create ${topic_id} \
    --project="${project_id}"
# --message-retention-duration=1h

# # * create subscription
# gcloud pubsub subscriptions create ${subscription_id} \
#     --topic=${topic_id} \
#     --bigquery-table="${project_id}:${dataset_id}.${table_id}" \
#     --use-table-schema

# https://pubsub.googleapis.com/v1/projects/dkg-phd-thesis/topics/bq-qualtrics-raw-responses-topic:publish


# functions-framework --target=main --host=localhost --port=8080
project_id=$(gcloud config get core/project)
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

fun_name="run-qualtrics-contacts"
region=$(gcloud config get run/region)
base_image="python311"
function="subscribe" # * this is the entry point when specified
exec_env="gen2"      # using default (gcloud auto selects); https://cloud.google.com/run/docs/about-execution-environments
memory="512Mi"
cpu=1
min_instances=1 # using default; https://cloud.google.com/sdk/gcloud/reference/run/deploy#--min-instances
timeout="300s"
concurrency=80 # using default; https://cloud.google.com/sdk/gcloud/reference/run/deploy#--concurrency

# printf "Note: The service account %s represents the identity of the \
# running function %s, and determines what permissions the function has.\n\n" "$sa_address" "$fun_name"

# gcloud run deploy $fun_name \
#     --region=$region \
#     --project=$project_id \
#     --service-account=$sa_address \
#     --base-image=$base_image \
#     --function=$function \
#     --memory=$memory \
#     --cpu=$cpu \
#     --timeout=$timeout \
#     --allow-unauthenticated

# https://cloud.google.com/sdk/gcloud/reference/run/deploy#--[no-]allow-unauthenticated

trigger_name="pubsub-trigger-run-qualtrics-contacts"
# gcloud eventarc triggers create $trigger_name \
#     --location=$region \
#     --destination-run-service=$fun_name \
#     --destination-run-region=$region \
#     --event-filters="type=google.cloud.pubsub.topic.v1.messagePublished" \
#     --service-account=$sa_address

gcloud eventarc triggers list --location=$region

TOPIC_ID=$(gcloud eventarc triggers describe $trigger_name \
    --location $region \
    --format='value(transport.pubsub.topic)')

gcloud pubsub topics publish $TOPIC_ID \
    --message="Hello World"

gcloud pubsub topics delete $topic_id
gcloud run services delete $fun_name
gcloud eventarc triggers delete $trigger_name

# #### !!
# #!/bin/bash

# # functions-framework --target=main --host=localhost --port=8080


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

# fun_name="run_contact_pipeline"
# region="us-east4"
# project_id=$(gcloud config get-value project)
# # * gcloud functions runtimes list
# runtime="python311"
# entry_point="main"
# memory="512MiB"
# cpu=1
# min_instances=1
# timeout="300s"
# concurrency=80

# printf "Note: The service account %s represents the identity of the \
# running function %s, and determines what permissions the function has.\n\n" "$sa_address" "$fun_name"

# gcloud functions deploy $fun_name \
#     --region=$region \
#     --project=$project_id \
#     --service-account=$sa_address \
#     --region=$region \
#     --runtime=$runtime \
#     --entry-point=$entry_point \
#     --memory=$memory \
#     --cpu=$cpu \
#     --min-instances=$min_instances \
#     --timeout=$timeout \
#     --concurrency=$concurrency \
#     --gen2 \
#     --trigger-http \
#     --allow-unauthenticated

# fun_url="$(gcloud functions describe run_contact_pipeline --gen2 --region us-east4 --format='get(serviceConfig.uri)')"
# echo $fun_url
# curl $fun_url

# curl $fun_url \
#     -H "Authorization: bearer $(gcloud auth print-identity-token \
#     --impersonate-service-account $sa_address)"

# # # ! TO DELETE RUN:
# # gcloud functions delete run_contact_pipeline --region=us-east4 --gen2
