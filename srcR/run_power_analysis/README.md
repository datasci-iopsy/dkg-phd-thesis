# run_power_analysis

Author & Maintainer: Demetrius K. Green ([Email](mailto:dkgreen.iopsych@gmail.com) | [GitHub](https://github.com/datasci-iopsy) | [LinkedIn](https://www.linkedin.com/in/dkgreen-io/))

- [run\_power\_analysis](#run_power_analysis)
- [Overview](#overview)
- [Requirements](#requirements)
  - [OS Compatibility](#os-compatibility)
  - [Dependencies](#dependencies)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

# Overview

The [run_power_analysis](/srcR/run_power_analysis/) program conducts a simulation-based sensitivity analysis to evaluate statistical power across a fully customizable design matrix of parameters. The program is fully compatible with macOS and Linux (i.e., Ubuntu), but not Windows. The program is designed to be run directly from the user's command line and does not require RStudio or any other IDE to generate results; simply clone the project repo and follow the instructions found in the [Usage](#usage) section.

# Requirements

The program is designed to run on macOS and Linux (i.e., Ubuntu) and requires a few dependencies to function properly. The following sections outline the requirements for running the program, including OS compatibility, R version, and other necessary tools.

## OS Compatibility

:white_check_mark: **macOS**: Fully tested and supported.

:warning: **Linux Distros**: 

- :white_check_mark: Ubuntu: Fully tested and supported.

- :warning: Debian, RHEL/CentOS, and other distros may require additional configuration or not function at all.

:x: **Windows**: Not supported due to fundamental differences in the command-line interface and file system architecture.

## Dependencies

The following dependencies are required to run the program successfully:

- `bash>=5.3.3(1)-release`
  - The program was developed using this version of bash, but is most likely compatible with earlier versions up to an unknown extent and perhaps other shells (e.g., `sh`, `zsh`, etc.).
- `R>=4.2.0`
  - The `renv==1.1.5` package handles dependencies across all the [srcR](/srcR/) programs, so only a handful of packages may need to be manually installed (e.g., `jsonlite` and `languageserver` for development outside of RStudio).
- `mail>=3.14`
  - This lightweight command-line utility is used to send emails to user comprising the output. It is automatically included in macOS, but follow this helpful [post](https://www.digitalocean.com/community/tutorials/send-email-linux-command-line) if not already installed on Linux.
- Notable optional dependencies:
  - *`git`* is highly recommended for version control and collaboration.
  - *`brew>=4.5.13`* is an exceptional third-party package manager for macOS.

# Usage

The [run_power_analysis](/srcR/run_power_analysis/) program is designed to be run directly from the command line. The following steps provide a quick start guide to running the program assuming the user already has `git` and a compatible version of R installed (i.e., `>=4.2.0`) on their system:

1. Clone the project repo.
    ```bash
    # clone the repo using HTTPS
    git clone https://github.com/datasci-iopsy/dkg-phd-thesis.git

    # or using SSH (if you have set up SSH keys)
    git clone git@github.com:datasci-iopsy/dkg-phd-thesis.git

    # or using GitHub CLI (gh) if installed
    gh repo clone datasci-iopsy/dkg-phd-thesis
    ```
    - *Note. The user can also download the project as a zip file and extract it to their desired location, but cloning the repo is recommended for version control and collaboration purposes.*

2. Navigate to the [srcR](/srcR/) directory and run the [run_renv_restore](../run_renv_restore.r) script to ensure that `renv` and other necessary R packages are installed.

    ```bash
    Rscript run_renv_restore.sh
    ```

    - *Note. The user also has the option to open the script and simply run it rather than sourcing it from the command line. This is particularly useful if the user is already working in RStudio or another IDE*.

3. Navigate to the [run_power_analysis](./) directory (i.e., the same directory as this README.md file).

:red_circle::red_circle::red_circle: **STOP: IMPORTANT** :red_circle::red_circle::red_circle:

4. Next, review and adjust the configuration file to ensure that the parameters are set to the user's desired values.
   - The config files are located in the [configs](./configs/) directory and include suffixes to differientiate versions. For example, the `.dev.yaml` suffix is used for development purposes and typically comprise fewer parameters and iterations, while the `.prod.yaml` suffix is used for production runs and should include a wider range of parameters and number of iterations.
   - The current process requires the user to manually specify which version of the program to run (see line 31 in the [run_power_analysis.sh](./run_power_analysis.sh) script) which will instantiate the corresponding config file to use. *This is a temporary solution until the author implements a more robust solution (e.g., command line arguments, etc.).*

:green_circle::green_circle::green_circle: **CONTINUE** :green_circle::green_circle::green_circle:

5. Once the desired config file has been finalized, ensure the correct version is set in the bash script before entering the following in the command line: 
   ```bash
   nohup bash run_power_analysis.sh > logs/run_power_analysis_$(date +"%Y%m%d_%H%M%S").log 2>&1 &
   ```
   - This command will run the program in the background, even if the session closes, allowing the user to continue with other tasks.

6. The program's standard output (i.e., stdout) will be printed to a log file and saved in the program's log directory.
7. Once the program has completed, the user can check the log file for any potential errors and review the output (i.e., .csv/.rds) which is redirected to the [data](./data/) directory.
   - *Note. The log and data directories are currently listed in the [.gitignore](../../.gitignore) file and thus are not tracked by version control. The program automatically creates the required directories not tracked by git. The log and data files will be named with a timestamp to ensure uniqueness and relatively easy identification of when the program was run.*

# Troubleshooting

The following sections provide troubleshooting tips for common issues, particularly in Linux, that may arise when running the [run_power_analysis](/srcR/run_power_analysis/) (e.g., incompatible version of R, over utilized kernels, etc.). See the collapsed sections below if the user is having trouble for additional information.

<details>

<summary>Having kernel issues?</summary>

```bash
# List all installed kernel images
dpkg --list | grep linux-image

# Check which kernel you are currently running (DO NOT remove this one)
uname -r

# Remove old kernel images and headers (replace with actual versions from Step 1)
# If you have other old kernels, remove them too (but keep current + one backup)
# Remove all packages with "rc" status (removed but config files remain)
sudo apt purge $(dpkg -l | awk '/^rc/ {print $2}')

# Clean up any remaining dependencies
sudo apt autoremove --purge

# Check boot space
df -h /boot

# Create configuration for dependency-based modules (smaller size)
sudo tee /etc/initramfs-tools/conf.d/modules <<EOF
MODULES=dep
COMPRESS=lz4
EOF

# Regenerate initramfs with optimized settings
sudo update-initramfs -u -k all

# Fix the broken initramfs-tools package
sudo apt-get install -f
sudo dpkg --configure -a

# Check current kernel
uname -r

# List remaining installed kernels (should only show 2)
dpkg --list | grep '^ii.*linux-image'

# Check boot space
df -h /boot

# Verify system package status
sudo apt-get check
```
</details>


<details>

<summary>Install or Update R in Linux</summary>
1. `wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | sudo tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc`
2. `sudo add-apt-repository "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/"`
3. `sudo apt update`
4. `sudo apt install r-base`

</details>

# Contributing

Contributions are welcome! If you have suggestions for improvements or find bugs, please open an issue or submit a pull request. In addition, if you have any questions or need assistance, feel free to reach out via [email](mailto:dkgreen.iopsych@gmail.com) or through the project's GitHub repository.