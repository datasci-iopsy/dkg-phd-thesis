#!/usr/bin/env bash
# bash run_power_analysis.sh > logs/run_power_analysis_$(date +"%Y%m%d_%H%M%S").log 2>&1 &

# Capture start time for overall timing
start_time=$(date +%s)
start_time_readable=$(date '+%Y-%m-%d %H:%M:%S')

# *** UPDATE ABSOLUTE PATH ***
src_dir="${HOME}/Documents/icloud-docs/prof-edu/projects/dkg-phd-thesis/srcR"
echo -e "Source directory: ${src_dir}\n"

# ****************************
proj_name='run_power_analysis'
echo -e "Project name: ${proj_name}\n"

proj_dir="${src_dir}/${proj_name}"
echo -e "Project directory: ${proj_dir}\n"

# *** UPDATE PROJECT VERSION ***
version='dev'
echo -e "Version: ${version}\n"

# ******************************
shared_utils_dir="${src_dir}/shared/utils"
echo -e "Shared utils directory: ${shared_utils_dir}\n"

common_utils_path="${shared_utils_dir}/common_utils.R"
echo -e "Shared common utils path: ${common_utils_path}\n"

utils_dir="${proj_dir}/utils"
echo -e "Project utils directory: ${utils_dir}\n"

config_dir="${proj_dir}/configs"
echo -e "Config directory: ${config_dir}\n"

config_path="${config_dir}/${proj_name}.${version}.yaml"
echo -e "Config path: ${config_path}\n"

# Define data and log directories
data_dir="${proj_dir}/data"

# Check if data directory exists, create if not
if [ ! -d "${data_dir}" ]; then
    echo "Data directory not found. Creating ${data_dir}..."
    mkdir -p "${data_dir}"
fi
echo -e "Data directory: ${data_dir}\n"

log_dir="${proj_dir}/logs"

# Check if log directory exists, create if not
if [ ! -d "${log_dir}" ]; then
    echo "Log directory not found. Creating ${log_dir}..."
    mkdir -p "${log_dir}"
fi
echo -e "Log directory: ${log_dir}\n"

# Function to log with timestamp
log_with_timestamp() {
    while IFS= read -r line; do
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $line"
    done
}

# Function to calculate and format elapsed time
calculate_elapsed_time() {
    local start=$1
    local end=$2
    local elapsed=$((end - start))
    
    local hours=$((elapsed / 3600))
    local minutes=$(((elapsed % 3600) / 60))
    local seconds=$((elapsed % 60))
    
    if [ $hours -gt 0 ]; then
        printf "%02d:%02d:%02d" $hours $minutes $seconds
    elif [ $minutes -gt 0 ]; then
        printf "%02d:%02d" $minutes $seconds
    else
        printf "%ds" $seconds
    fi
}

# Add system resource monitoring and timing info
echo "Process started at: ${start_time_readable}" | log_with_timestamp
echo "System info at start" | log_with_timestamp
echo "Available cores: $(sysctl -n hw.ncpu)" | log_with_timestamp
echo "Physical memory: $(sysctl -n hw.memsize | awk '{printf "%.1f GB", $1/1024/1024/1024}')" | log_with_timestamp
echo "Available memory (vm_stat): $(vm_stat | grep 'Pages free' | awk '{printf "%.1f GB", $3 * 4096 / 1024 / 1024 / 1024}')" | log_with_timestamp
echo "Available memory (top): $(top -l 1 | grep -E '^CPU|^Phys')" | log_with_timestamp

if [[ "${proj_dir}" == "$(pwd)" ]]; then
    echo "Project Directory & Current Working Directory Match" | log_with_timestamp
    echo "Initiating ${proj_name}" | log_with_timestamp
    
    # Capture R script start time
    r_start_time=$(date +%s)
    
    # Run R script with timestamped logging
    {
        Rscript "./scripts/${proj_name}.R" \
            ${src_dir} \
            ${proj_name} \
            ${version} \
            ${common_utils_path} \
            ${config_path} \
            ${utils_dir} \
            ${data_dir} 2>&1 | log_with_timestamp
            
    } || {
        echo "ERROR: R script execution failed with exit code $?" | log_with_timestamp
        exit 1
    }
    
    # Calculate R script elapsed time
    r_end_time=$(date +%s)
    r_elapsed=$(calculate_elapsed_time $r_start_time $r_end_time)
    echo "R script completed in: ${r_elapsed}" | log_with_timestamp
    
    # Calculate total elapsed time
    end_time=$(date +%s)
    end_time_readable=$(date '+%Y-%m-%d %H:%M:%S')
    total_elapsed=$(calculate_elapsed_time $start_time $end_time)
    
    echo "Process completed at: ${end_time_readable}" | log_with_timestamp
    echo "Total execution time: ${total_elapsed}" | log_with_timestamp
    
else
    echo "ERROR: Project Directory & Current Working Directory DO NOT Match" | log_with_timestamp
    echo "Current directory: $(pwd)" | log_with_timestamp
    echo "Expected directory: ${proj_dir}" | log_with_timestamp
    exit 1
fi
