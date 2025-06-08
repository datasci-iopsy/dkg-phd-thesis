#!/bin/bash

readonly SERVICE_ACCOUNT_NAME="dkg-cloud-funs"
readonly SERVICE_ACCOUNT_DISPLAY_NAME="DKG Cloud Functions Service Account"

gcloud iam service-accounts create "{$SERVICE_ACCOUNT_NAME}" \
    --display-name="{$SERVICE_ACCOUNT_DISPLAY_NAME}"

readonly SERVICE_ACCOUNT_EMAIL=$(gcloud iam service-accounts list \
    --filter="displayName~'${SERVICE_ACCOUNT_NAME}'" \
    --format="value(email)")

# echo $sa_name
# echo $sa_address

if [ -z "${SERVICE_ACCOUNT_EMAIL}" ]; then
    echo "Service account not found!"
    exit 1
fi

readonly PROJECT_ID="dkg-phd-thesis"

roles=(
    "roles/bigquery.dataEditor"
    "roles/bigquery.jobUser"
    "roles/cloudfunctions.invoker"
    "roles/iam.serviceAccountTokenCreator"
    "roles/run.invoker"
    "roles/run.servicesInvoker"
    "roles/secretmanager.secretAccessor"
)

for role in "${roles[@]}"; do
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
        --role="${role}"
done
