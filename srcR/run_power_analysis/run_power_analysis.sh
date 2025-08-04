#!/usr/bin/env bash
# TO RUN: nohup bash run_power_analysis.sh > logs/run_power_analysis_$(date +"%Y%m%d_%H%M%S").log 2>&1 &

# capture start time for overall timing
start_time=$(date +%s)
start_time_readable=$(date '+%Y-%m-%d %H:%M:%S')
# start_time_log=$(date +"%Y%m%d_%H%M%S")

echo -e "\nCurrent working directory: $(pwd)"
endpath=$(basename "$(pwd)")
echo -e "Basename: ${endpath}\n"

# *** ALTHOUGH HARD-CODED, TREAT AS IMMUTABLE ***
proj_name='run_power_analysis' # ? maybe use variable instead of hard-coded value?
echo -e "Project name: ${proj_name}\n"
# **********************************************

if [ ${endpath} == ${proj_name} ]; then
    echo -e "Current directory is ${endpath} and being moved up one level to srcR..."
    cd ..
fi
echo -e "New working directory: $(pwd)\n"

src_dir=$(pwd)
echo -e "Source directory: ${src_dir}\n"

proj_dir="${src_dir}/${proj_name}"
echo -e "Project directory: ${proj_dir}\n"

# *** UPDATE BASED ON ENV RUN ***
version='prod'
echo -e "Version: ${version}\n"
# *******************************

shared_utils_dir="${src_dir}/shared/utils"
echo -e "Shared utils directory: ${shared_utils_dir}\n"

common_utils_path="${shared_utils_dir}/common_utils.r"
echo -e "Shared common utils path: ${common_utils_path}\n"

utils_dir="${proj_dir}/utils"
echo -e "Project utils directory: ${utils_dir}\n"

config_dir="${proj_dir}/configs"
echo -e "Config directory: ${config_dir}\n"

config_path="${config_dir}/${proj_name}.${version}.yaml"
echo -e "Config path: ${config_path}\n"

# define data dir; check if it exists, create if not
data_dir="${proj_dir}/data"
if [ ! -d "${data_dir}" ]; then
    echo "Data directory not found. Creating ${data_dir}..."
    mkdir -p "${data_dir}"
fi
echo -e "Data directory: ${data_dir}\n"

# define log dir; check if it exists, create if not
log_dir="${proj_dir}/logs"
if [ ! -d "${log_dir}" ]; then
    echo "Log directory not found. Creating ${log_dir}..."
    mkdir -p "${log_dir}"
fi
echo -e "Log directory: ${log_dir}\n"

# function to log with timestamp
log_with_timestamp() {
    while IFS= read -r line; do
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $line"
    done
}

# function to calculate and format elapsed time
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

# cross-platform system info
get_system_info() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        echo "Available cores: $(sysctl -n hw.ncpu)" | log_with_timestamp
        echo "Physical memory: $(sysctl -n hw.memsize | awk '{printf "%.1f GB", $1/1024/1024/1024}')" | log_with_timestamp
        echo "Available memory: $(vm_stat | grep 'Pages free' | awk '{printf "%.1f GB", $3 * 4096 / 1024 / 1024 / 1024}')" | log_with_timestamp
    elif [[ "$OSTYPE" == "linux"* ]]; then
        # Linux
        echo "Available cores: $(nproc)" | log_with_timestamp
        echo "Physical memory: $(free -h | awk '/^Mem:/ {print $2}')" | log_with_timestamp
        echo "Available memory: $(free -h | awk '/^Mem:/ {print $7}')" | log_with_timestamp
    else
        echo "OS is not compatible with this project..."
    fi
}

echo "Process started at (human): ${start_time_readable}" | log_with_timestamp
echo "Process started at (machine): ${start_time}" | log_with_timestamp
echo "System info at start listed as follows:" | log_with_timestamp
get_system_info

# pre-flight checks and initiate process
if [[ "$(pwd)" == ${src_dir} ]]; then
    echo "Project Directory & Current Working Directory Match" | log_with_timestamp
    echo "Initiating ${proj_name}..." | log_with_timestamp
    
    # capture R script start time
    r_start_time=$(date +%s)
    
    # run R script with timestamped logging
    {
        Rscript "${proj_dir}/scripts/${proj_name}.r" \
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
    
    # # calculate R script elapsed time
    # r_end_time=$(date +%s)
    # r_elapsed=$(calculate_elapsed_time $r_start_time $r_end_time)
    # echo "R script completed in: ${r_elapsed}" | log_with_timestamp
    
    # calculate total elapsed time
    end_time=$(date +%s)
    end_time_readable=$(date '+%Y-%m-%d %H:%M:%S')
    total_elapsed=$(calculate_elapsed_time $start_time $end_time)
    
    echo "Process started at: ${start_time_readable}" | log_with_timestamp
    echo "Process completed at: ${end_time_readable}" | log_with_timestamp
    echo "Total execution time: ${total_elapsed}" | log_with_timestamp
    
else
    echo "ERROR: Project Directory & Current Working Directory DO NOT Match" | log_with_timestamp
    echo "Current directory: $(pwd)" | log_with_timestamp
    echo "Expected directory: ${proj_dir}" | log_with_timestamp
    exit 1
fi

echo -e "Bash process complete. Please review appropriate log in the following directory: ${log_dir}"

# # * WARNING: Linux users may have to install mail from apt: 
# # * https://www.digitalocean.com/community/tutorials/send-email-linux-command-line
# email_subject=${proj_name}
# email_recipient="dkgreen@ncsu.edu"
# email_message="Attached is a compressed archive containing all output files generated from the '${proj_name}' script."

# # create tar archive of all files in data directory
# tar_file="${proj_name}_data_${start_time}.tar.gz"
# tar -czf "${tar_file}" -C "${data_dir}" .

# # send email with single archive attachment
# echo "${email_message}" | mail -s "${email_subject}" -A "${tar_file}" "${email_recipient}"

# # clean up temporary archive (optional)
# rm "${tar_file}"

# echo -e "Email sent and temporary tar file deleted."

# # # todo: figure out how to include multiple attachments from different directories;
# # # TODO: better yet, rsync would be even more seemless!
# # email_subject=${proj_name}
# # email_recipient="dkgreen@ncsu.edu"
# # email_message="Attached is a compressed archive containing all output files and log file generated from the '${proj_name}' script."

# # # specify both the data directory and log file explicitly
# # tar_file="${proj_name}_results.tar.gz"
# # log_file="${log_dir}/${proj_name}_${start_time_log}.log"  # Replace with actual log file path

# # tar -czf "${tar_file}" -C "${data_dir}"/* "${log_file}"

# # # send email
# # echo "${email_message}" | mail -s "${email_subject}" -A "${tar_file}" "${email_recipient}"

# # # clean up
# # rm "${tar_file}"
