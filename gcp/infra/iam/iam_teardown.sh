#!/bin/bash

readonly SERVICE_ACCOUNT_NAME="dkg-cloud-funs"
readonly SERVICE_ACCOUNT_EMAIL=$(gcloud iam service-accounts list \
    --filter="displayName~'${SERVICE_ACCOUNT_NAME}'" \
    --format="value(email)")

echo $SERVICE_ACCOUNT_NAME
echo $SERVICE_ACCOUNT_EMAIL



if [ -z "${SERVICE_ACCOUNT_EMAIL}" ]; then
    echo "Service account not found!"
    exit 1
fi

gcloud iam service-accounts delete \
    "${SERVICE_ACCOUNT_EMAIL}"
