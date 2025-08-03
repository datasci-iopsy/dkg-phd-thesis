# run_power_analysis

Author: Demetrius K. Green



## System Requirements
- **macOS**: Fully tested and supported.
- Linux: The main program is expected to work, but the run_power_analysis.sh script requires modification as it uses macOS-native commands for memory checks.
- Windows: Not supported due to fundamental differences in the command-line interface and file system architecture.

## Program Dependencies
- Bash (`>=5.3.3(1)-release`)
  - *Note*. The author built the program using this version of bash but is most likely compatible with earlier versions.
- R (`>= 4.2.0`)
  - See [DESCRIPTION](./DESCRIPTION) for specific R packages and relevant dependencies.
- *Homebrew (`>=4.5.13`) is optional but an exceptional package manager for macOS*.
## To Run

MacOS Run:
1. Navigate to the [run_power_analysis project directory](./) (i.e., the same directory as this README.md file).
2. Enter `bash run_power_analysis.sh > logs/run_power_analysis_$(date +"%Y%m%d_%H%M%S").log 2>&1 &` in the terminal/commandline.
3. The program's standard output (i.e., stdout) will be printed to a log file and saved in the program's log directory.
   1. Note. The log directory is currently listed in the [.gitignore](../../.gitignore) file and thus is not tracked by version control.


Linux Run:
1. `wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | sudo tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc`
2. `sudo apt update`
3. `sudo apt install r-base`
