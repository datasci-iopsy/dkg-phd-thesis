#!/usr/bin/env bash
set -euo pipefail

# Provision and load syn_qualtrics.stg_intake_responses.
# Schema is cloned from the production table. Idempotent -- safe to rerun.

PROJECT="dkg-phd-thesis"
DATASET="syn_qualtrics"
TABLE="stg_intake_responses"
SOURCE_TABLE="${PROJECT}.qualtrics.${TABLE}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_FILE="${SCRIPT_DIR}/../data/import/claude_gen_syn_intake_responses_20260223.csv"

[[ -f "${DATA_FILE}" ]] || { echo "ERROR: data file not found: ${DATA_FILE}" >&2; exit 1; }

# -- 1. Dataset ----------------------------------------------------------
if ! bq show --dataset --project_id="${PROJECT}" "${PROJECT}:${DATASET}" >/dev/null 2>&1; then
    echo "Creating dataset ${DATASET}..."
    bq mk \
        --dataset \
        --location=US \
        --project_id="${PROJECT}" \
        "${PROJECT}:${DATASET}"
fi

# -- 2. Table (schema cloned from production) ----------------------------
bq query \
    --use_legacy_sql=false \
    --project_id="${PROJECT}" \
    --location=US \
    "CREATE TABLE IF NOT EXISTS \`${PROJECT}.${DATASET}.${TABLE}\`
     LIKE \`${SOURCE_TABLE}\`;"

# -- 3. Truncate for idempotency -----------------------------------------
bq query \
    --use_legacy_sql=false \
    --project_id="${PROJECT}" \
    --location=US \
    "TRUNCATE TABLE \`${PROJECT}.${DATASET}.${TABLE}\`;"

# -- 4. Load CSV ---------------------------------------------------------
echo "Loading ${DATA_FILE}..."
bq load \
    --source_format=CSV \
    --skip_leading_rows=1 \
    --project_id="${PROJECT}" \
    --location=US \
    "${PROJECT}:${DATASET}.${TABLE}" \
    "${DATA_FILE}"

# -- 5. Verify -----------------------------------------------------------
META=$(bq show --format=json "${PROJECT}:${DATASET}.${TABLE}")
echo "${META}" | jq -r '"Rows: \(.numRows)  Bytes: \(.numBytes)  Columns: \(.schema.fields | length)  Modified: \(.lastModifiedTime | tonumber / 1000 | gmtime | strftime("%Y-%m-%dT%H:%M:%SZ"))"'
