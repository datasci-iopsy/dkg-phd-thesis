#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------
PROJECT="dkg-phd-thesis"
DATASET="syn_qualtrics"
TABLE="stg_intake_responses"
SOURCE_DATASET="qualtrics"
SOURCE_TABLE="${PROJECT}.${SOURCE_DATASET}.${TABLE}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_FILE="${SCRIPT_DIR}/../data/import/claude_gen_syn_intake_responses_20260223.csv"

# -------------------------------------------------------------------
# 0. Create dataset if it does not exist
# -------------------------------------------------------------------
echo "Creating dataset ${PROJECT}.${DATASET} if it does not exist..."

if ! bq show \
	--dataset \
	--project_id="${PROJECT}" \
	"${PROJECT}:${DATASET}" >/dev/null 2>&1; then
	bq mk \
		--dataset \
		--location="US" \
		--project_id="${PROJECT}" \
		"${PROJECT}:${DATASET}"
	echo "Dataset ${DATASET} created."
else
	echo "Dataset ${DATASET} already exists -- skipping."
fi

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
