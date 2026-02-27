#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------
PROJECT="dkg-phd-thesis"
DATASET="syn_qualtrics"
TABLE="stg_followup_responses"
# SOURCE_TABLE="${PROJECT}.${DATASET}.followup_responses"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_FILE="${SCRIPT_DIR}/../schemas/stg_syn_followup_responses.json"
DATA_FILE="${SCRIPT_DIR}/../data/import/claude_gen_syn_followup_responses_20260223.csv"

# -------------------------------------------------------------------
# 1. Create table (schema only, no data)
# -------------------------------------------------------------------
echo "Creating table ${PROJECT}.${DATASET}.${TABLE} if it does not exist..."

if ! bq mk \
	--table \
	--schema="${SCHEMA_FILE}" \
	--project_id="${PROJECT}" \
	--location="US" \
	"${PROJECT}:${DATASET}.${TABLE}" 2>&1; then
	# Check if table already exists
	if bq show "${PROJECT}:${DATASET}.${TABLE}" >/dev/null 2>&1; then
		echo "Table ${PROJECT}.${DATASET}.${TABLE} already exists, skipping creation."
	else
		echo "Error: Failed to create table ${PROJECT}:${DATASET}.${TABLE}" >&2
		exit 1
	fi
fi

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
