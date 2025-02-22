#!/bin/bash

# grant BigQuery permissions to Pub/Sub service account; should only have to run once
gcloud projects add-iam-policy-binding dkg-phd-thesis \
    --member="serviceAccount:service-312811716490@gcp-sa-pubsub.iam.gserviceaccount.com" \
    --role="roles/bigquery.dataEditor" \
    --project="dkg-phd-thesis"
