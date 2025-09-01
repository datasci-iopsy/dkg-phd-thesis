# run_power_analysis

Author & Maintainer: Demetrius K. Green ([Email](mailto:dkgreen.iopsych@gmail.com) | [GitHub](https://github.com/datasci-iopsy) | [LinkedIn](https://www.linkedin.com/in/dkgreen-io/))

- [run\_power\_analysis](#run_power_analysis)
- [Overview](#overview)
- [Requirements](#requirements)
  - [OS Compatibility](#os-compatibility)
  - [Dependencies](#dependencies)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)
    - [](#)
- [Contributing](#contributing)

# Overview

The [run_power_analysis](/srcR/run_power_analysis/) program conducts a simulation-based sensitivity analysis based on the work of *Arend & Schäfer 2019* to evaluate statistical power across a fully customizable design matrix of parameters. The program is fully compatible with macOS and Linux (i.e., Ubuntu), but not Windows. The program leverages `furrr` (for parallelization) and `simr` packages in R and is designed to run from the user's command line, eliminating the need for IDEs to generate and review the results (e.g., RStudio, VS Code, etc.); To get started, simply clone the project repo and follow the instructions found in the [Usage](#usage) section.

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

2. Run the command `make power_analysis` from the project root directory.

3. The program's standard output (i.e., stdout) will be printed to a log file and saved in the program's log directory.

4. Once the program has completed, the user can check the log file for any potential errors and review the output (i.e., .csv/.rds) which is redirected to the data directory.
   - *Note. The log and data directories are currently listed in the [.gitignore](../../.gitignore) file and thus are not tracked by version control; the program automatically creates the required directories not tracked by git. The log and data files will be named with a timestamp to ensure uniqueness and relatively easy identification of when the program was run.*

# Troubleshooting

The following sections provide troubleshooting tips for common issues, particularly in Linux, that may arise when running the [run_power_analysis](/srcR/run_power_analysis/) (e.g., incompatible version of R, over utilized kernels, etc.). See the collapsed sections below if the user is having trouble for additional information.

<details>

<summary>Long-running processes?</summary>
Since the program is based on running a number of iterations across a design matrix of parameters, the time it takes for the program to complete can vary significantly based on the complexity of the matrix. For example, the following parameter matrix was used for the author's dissertation (i.e., production run):

###
- Level 1 sample size (3)
- Level 2 sample sizes (200, 400, 600, 800, 1000)
- Level 1 direct effect size (0.10, 0.30, 0.50)
- Level 2 direct effect size (0.10, 0.30, 0.50)
- Cross-level effect size (0.10, 0.30, 0.50)
- ICC values (0.10, 0.30, 0.50)
- Random slope variance values (0.01, 0.09, 0.25)
- Significance level (0.05)

This setup yielded a 5 × 3 × 3 × 3 × 3 × 3 = **1,215 parameter matrix** where each cell represented a unique combination of parameters. The simulations were run for 1,000 iterations per cell, resulting in a total of **1,215,000 simulations**. Suffice to say, this is a very large matrix and will take a long time to run on most local systems. Here is a snapshot of the author's local setup: 

```bash
Software:

    System Software Overview:

      System Version: macOS 15.5 (24F74)
      Kernel Version: Darwin 24.5.0
      Boot Volume: Macintosh HD
      Boot Mode: Normal
      Computer Name: ${hostname}
      User Name: ${whoami}
      Secure Virtual Memory: Enabled
      System Integrity Protection: Enabled
      Time since boot: X days, X hours, X minutes

Hardware:

    Hardware Overview:

      Model Name: MacBook Pro
      Model Identifier: MacBookPro18,4
      Model Number: Z15H00106LL/A
      Chip: Apple M1 Max
      Total Number of Cores: 10 (8 performance and 2 efficiency)
      Memory: 32 GB
      System Firmware Version: 11881.121.1
      OS Loader Version: 11881.121.1
      Serial Number (system): XXXXXXXXXX
      Hardware UUID: 00000000-0000-0000-0000-000000000000
      Provisioning UDID: 00000000-000000000000000E
```

Here is a snippet of the output from the respective log file: 

```bash
[2025-08-05 14:30:52] Rows: 3,645
[2025-08-05 14:30:52] Columns: 16
...
[2025-08-05 14:30:52] Results Summary:
[2025-08-05 14:30:52] Total parameter combinations: 1215 
[2025-08-05 14:30:52] Successful runs: 3645 
[2025-08-05 14:30:52] Failed runs: 0 
...
[2025-08-05 14:30:52] Results saved as power_analysis_results_20250805_143050.rds/csv
[2025-08-05 14:30:52] Process started at: 2025-08-04 19:53:31
[2025-08-05 14:30:52] Process completed at: 2025-08-05 14:30:52
[2025-08-05 14:30:52] Total execution time: 18:37:21
Bash process complete. Please review appropriate log in the following directory: <user_path>/dkg-phd-thesis/srcR/run_power_analysis/logs
```

As you can see, it took the system over 18 hours to complete the run. This overhead could (and most likely will) be reduced by leveraging a cloud-based virtual machine (VM), such as Google Cloud platform's (GCP) compute engine API, to run the simulations in parallel on a larger scale. For example, a virtual machine (VM) instance with the following specs could theoretically run the simulations in 2 to 5 hours, albeit at a literal cost :money_with_wings::money_with_wings::money_with_wings::

- Compute-Optimized C2D (Best Price-Performance)
    - Machine Type: `c2d-highcpu-56` or `c2d-highcpu-112`
    - 56-112 vCPUs, 4-8 GB RAM per vCPU
</details>

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