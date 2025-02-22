#!/bin/bash

project_id="$(gcloud config get project)"
# project_id="$(gcloud info --format='value(config.project)')"
dataset_id="dkg_phd_thesis_db"
table_id="raw_contacts"

topic_id="bq-qualtrics-raw-responses-topic"
subscription_id="bq-qualtrics-raw-responses-subscription"

# # ! TO DELETE RUN COMMAND BELOW:
# gcloud pubsub topics delete ${topic_id} \
#     --project="${project_id}"

# * create topic
gcloud pubsub topics create ${topic_id} \
    --message-retention-duration=1h \
    --project="${project_id}"

# * create subscription
gcloud pubsub subscriptions create ${subscription_id} \
    --topic=${topic_id} \
    --bigquery-table="${project_id}:${dataset_id}.${table_id}" \
    --use-table-schema

# https://pubsub.googleapis.com/v1/projects/dkg-phd-thesis/topics/bq-qualtrics-raw-responses-topic:publish