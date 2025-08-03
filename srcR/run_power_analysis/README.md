# run_power_analysis

Author: Demetrius K. Green



## Operating System (OS) Requirements
- **macOS**: Fully tested and supported.
- **Linux**: Fully tested and supported using Ubuntu distro, but may require some additional overhead (see Linux Run section).
  - *Note*. Debian and RHEL/CentOS may not function properly.
- ~~Window~~s: Not supported due to fundamental differences in the command-line interface and file system architecture.

## Program Requirements
- Bash (`>=5.3.3(1)-release`)
  - The author built the program using this version of bash but is most likely compatible with earlier versions up to an unknown extent.
- R (`>= 4.2.0`)
  - The package `renv` handles the R dependencies across this project so only a handful of manual packages may need to be downloaded.
  - The author developed this project using VS Code, so functionality using RStudio is unknown. Users should be able to generate the output using only the command line.
- *Homebrew (`>=4.5.13`)* is optional but an exceptional package manager for macOS.
- *apt* and *dpkg* are used by Ubuntu for package management.

## To Run

### MacOS Run:

Running the program on macOS is relatively straightforward.

1. Open and run the [run_renv_restore](../run_renv_restore.r)
   1. This will ensure that the necessary packages are installed.
2. Navigate to the [run_power_analysis project directory](./) (i.e., the same directory as this README.md file).
3. Enter the following in the command line: 
   
   `bash run_power_analysis.sh > logs/run_power_analysis_$(date +"%Y%m%d_%H%M%S").log 2>&1 &`

   1. Manually entering the code in the command line ensures that the bash script orchestrates the entire process and is logged approrpriately.
4. The program's standard output (i.e., stdout) will be printed to a log file and saved in the program's log directory.
   1. Note. The log directory is currently listed in the [.gitignore](../../.gitignore) file and thus is not tracked by version control.


### Linux Run:

The steps to run the program on Linux are ieentical to macOS **IF** the user already has a compatible version of R installed (i.e., `>=4.2.0`). The author encountered various issues when developing on Linux (e.g., incompatible version of R, over utilized kernels, etc.). See the collapsed sections immediately below if the user is having trouble instantiating the program.

<details>

<summary>Having kernel issues?</summary>

```bash
# List all installed kernel images
dpkg --list | grep linux-image

# Check which kernel you're currently running (DO NOT remove this one)
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