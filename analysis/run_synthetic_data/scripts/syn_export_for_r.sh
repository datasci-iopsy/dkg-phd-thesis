#!/usr/bin/env bash
# =============================================================================
# analysis/run_synthetic_data/scripts/syn_export_for_r.sh
#
# Exports fct_syn_all_responses from BigQuery to a dated CSV in data/export/.
# Run this before corr_analysis.R whenever the BigQuery fact table changes.
# =============================================================================
set -euo pipefail

PROJECT="dkg-phd-thesis"
DATASET="qualtrics"
TABLE="fct_syn_all_responses"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORT_DIR="$(cd "${SCRIPT_DIR}/../data/export" && pwd)"
DATE_TAG="$(date +%Y%m%d)"
OUT_FILE="${EXPORT_DIR}/${TABLE}_${DATE_TAG}.csv"

echo "Exporting ${TABLE} → ${OUT_FILE}"

bq query \
    --project_id=${PROJECT} \
    --location=US \
    --use_legacy_sql=false \
    --format=csv \
    --max_rows=10000 \
    "SELECT * FROM \`${PROJECT}.${DATASET}.${TABLE}\` ORDER BY followup_date, prolific_pid, timepoint" \
    > "${OUT_FILE}"

ROW_COUNT=$(tail -n +2 "${OUT_FILE}" | wc -l | tr -d ' ')
echo "Done. ${ROW_COUNT} rows written to ${OUT_FILE}"
