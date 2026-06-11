#!/usr/bin/env bash
# =============================================================================
# analysis/run_study_analysis/scripts/export_study_fct_panel_responses_csv.sh
#
# Runs fct_panel_responses.sql in BigQuery (requires int_* tables to exist),
# then exports the result to data/export/qualtrics_fct_panel_responses.csv
# =============================================================================
set -euo pipefail

PROJECT="dkg-phd-thesis"
DATASET="qualtrics"
TABLE="fct_panel_responses"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="${SCRIPT_DIR}/sql/${TABLE}.sql"
EXPORT_DIR="$(cd "${SCRIPT_DIR}/../data/export" && pwd)"
OUT_FILE="${EXPORT_DIR}/${DATASET}_${TABLE}.csv"

echo "Rebuilding ${TABLE} from ${SQL_FILE}"
bq query \
	--project_id="${PROJECT}" \
	--location=US \
	--use_legacy_sql=false \
	<"${SQL_FILE}"

echo "Exporting ${TABLE} -> ${OUT_FILE}"

MAX_ROWS=2000

bq query \
	--project_id="${PROJECT}" \
	--location=US \
	--use_legacy_sql=false \
	--format=csv \
	--max_rows="${MAX_ROWS}" \
	"SELECT * FROM \`${PROJECT}.${DATASET}.${TABLE}\` ORDER BY followup_date DESC, response_id, timepoint" \
	>"${OUT_FILE}"

ROW_COUNT=$(tail -n +2 "${OUT_FILE}" | wc -l | tr -d ' ')
if [ "${ROW_COUNT}" -ge "${MAX_ROWS}" ]; then
	echo "WARNING: Row count (${ROW_COUNT}) reached max_rows limit. Data may be truncated!"
fi
echo "Done. ${ROW_COUNT} rows written to ${OUT_FILE}"
