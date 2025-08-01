#!/usr/bin/env bash

# current working directory should be within this project already but verify
echo "Current working directory: $(pwd)"

proj_dir=$(pwd)
proj_name='run_power_analysis'

# *** UPDATE ***
version='dev'
# **************

echo "Initiating ${proj_name}"
Rscript "${proj_dir}/scripts/${proj_name}.R" ${version}

echo "${proj_name} finished..."
