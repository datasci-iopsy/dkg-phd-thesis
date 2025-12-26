#!/bin/bash

# Copy shared utilities into function directory before deploy
cp -r ../shared/ ../cloud_run_functions/run_qualtrics_scheduling/shared/

gcloud functions deploy run-qualtrics-scheduling \
        --gen2 \
        --runtime=python312 \
        --region=us-central1 \
        --source=functions/qualtrics_ingestion \
        --entry-point=main \
        --trigger-http \
        --set-secrets=QUALTRICS_API_KEY=dkg-qualtrics-api-key:latest,QUALTRICS_WEBHOOK_SECRET=dkg-qualtrics-webhook-secret:latest

# Clean up copied files
rm -rf functions/qualtrics_ingestion/shared/
