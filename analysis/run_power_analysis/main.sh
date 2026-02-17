#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# main.sh - Thin wrapper for run_power_analysis
#
# Handles process lifecycle (log redirection, backgrounding, wall-clock time).
# All application logic (path resolution, config, renv, etc.) lives in R.
#
# Usage:
#   bash main.sh <version>
#   nohup bash main.sh dev 2>&1 &
# ---------------------------------------------------------------------------

set -euo pipefail

version="${1:?ERROR: version argument required (dev or prod)}"

# resolve this script's directory regardless of where invoked from
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ensure log directory exists
log_dir="${script_dir}/logs"
mkdir -p "${log_dir}"

# log file with timestamp
log_file="${log_dir}/run_power_analysis_$(date +"%Y%m%d_%H%M%S").log"

# redirect all output to log file while preserving terminal output
exec > >(tee -a "${log_file}") 2>&1

start_time=$(date +%s)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting run_power_analysis (version: ${version})"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Log file: ${log_file}"

# hand off to R -- all orchestration logic lives there
Rscript "${script_dir}/scripts/run_power_analysis.r" --version "${version}" 2>&1

exit_code=$?

end_time=$(date +%s)
elapsed=$(( end_time - start_time ))
printf "[$(date '+%Y-%m-%d %H:%M:%S')] Total wall-clock time: %02d:%02d:%02d\n" \
    $((elapsed / 3600)) $(((elapsed % 3600) / 60)) $((elapsed % 60))

if [ ${exit_code} -ne 0 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: R script exited with code ${exit_code}"
    exit ${exit_code}
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Process complete. Log saved to: ${log_file}"
