#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------
PROJECT="dkg-phd-thesis"
DATASET="qualtrics"
TABLE="syn_intake_responses"
SOURCE_TABLE="${PROJECT}.${DATASET}.intake_responses"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_FILE="${SCRIPT_DIR}/../data/claude-syn-data-raw-20260223.csv"

# -------------------------------------------------------------------
# 1. Create table (schema only, no data)
# -------------------------------------------------------------------
echo "Creating table ${PROJECT}.${DATASET}.${TABLE} if it does not exist..."

bq query \
  --use_legacy_sql=false \
  --project_id="${PROJECT}" \
  --location="US" \
  "CREATE TABLE IF NOT EXISTS \`${PROJECT}.${DATASET}.${TABLE}\`
   LIKE \`${SOURCE_TABLE}\`;"

# -------------------------------------------------------------------
# 2. Truncate table (data only, maintain schema)
# -------------------------------------------------------------------
echo "Truncating table ${PROJECT}.${DATASET}.${TABLE}..."

bq query \
  --use_legacy_sql=false \
  --project_id="${PROJECT}" \
  --location="US" \
  "TRUNCATE TABLE \`${PROJECT}.${DATASET}.${TABLE}\`;"

# -------------------------------------------------------------------
# 3. Load CSV data into the table
# -------------------------------------------------------------------
echo "Loading data from ${DATA_FILE}..."

bq load \
  --source_format=CSV \
  --skip_leading_rows=1 \
  --project_id="${PROJECT}" \
  --location="US" \
  "${PROJECT}:${DATASET}.${TABLE}" \
  "${DATA_FILE}"

echo "Done. Data loaded into ${PROJECT}.${DATASET}.${TABLE}."
