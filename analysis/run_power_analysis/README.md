# run_power_analysis

Author & Maintainer: Demetrius K. Green ([Email](mailto:dkgreen.iopsych@gmail.com) | [GitHub](https://github.com/datasci-iopsy) | [LinkedIn](https://www.linkedin.com/in/dkgreen-io/))

- [run\_power\_analysis](#run_power_analysis)
- [Overview](#overview)
- [Directory Structure](#directory-structure)
- [Requirements](#requirements)
  - [OS Compatibility](#os-compatibility)
  - [Dependencies](#dependencies)
- [Configuration](#configuration)
- [Usage](#usage)
- [Output](#output)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

# Overview

The `run_power_analysis` program conducts a simulation-based sensitivity
analysis based on the work of *Arend & Schafer (2019)* to evaluate statistical
power across a fully customizable design matrix of parameters for two-level
(multilevel) models. The program evaluates power for three fixed effects --
Level 1 direct, Level 2 direct, and cross-level interaction -- using Monte
Carlo simulations via the `simr` package with Kenward-Roger tests.

The program builds a full factorial grid from configuration parameters,
distributes the grid across parallel workers via `furrr`, and saves timestamped
results. It is designed to run from the command line, eliminating the need for
IDEs (e.g., RStudio, VS Code).

The architecture follows a thin-wrapper pattern: `main.sh` handles process
lifecycle (log file creation, wall-clock timing), while `run_power_analysis.r`
owns all application logic (path resolution, configuration, renv activation,
parallel execution, and output).

# Directory Structure

```
analysis/
  run_power_analysis/
    configs/
      run_power_analysis.dev.yaml     # Small grid, low sim count for testing
      run_power_analysis.prod.yaml    # Full factorial grid for dissertation
    data/                             # Output .rds/.csv (gitignored, created at runtime)
    figs/                             # Figures (gitignored, created at runtime)
    logs/                             # Timestamped log files (gitignored, created at runtime)
    scripts/
      run_power_analysis.r            # Main orchestration script
    utils/
      power_analysis_utils.r          # Simulation engine
    main.sh                           # Thin bash wrapper
    README.md                         # This file
  shared/
    utils/
      common_utils.r                  # Shared utilities (logging, config, etc.)
```

The `data/`, `logs/`, and `figs/` directories are created automatically at
runtime and should be listed in `.gitignore`.

# Requirements

## OS Compatibility

**macOS**: Fully tested and supported.

**Linux (Ubuntu)**: Fully tested and supported. Other distros (Debian,
RHEL/CentOS) may require additional configuration.

**Windows**: Not supported. The parallel backend uses `future::plan(multicore)`
on Unix systems and falls back to `multisession` on Windows, but the bash
wrapper and overall pipeline are not tested on Windows.

## Dependencies

**System requirements:**

- `bash` (any modern version; developed on 5.x)
- `R >= 4.2.0`
- `Python` (required by the `argparse` R package via `findpython`)

**R package management:**

All R package dependencies are managed by `renv`. The `renv.lock` file at the
project root pins exact package versions. After cloning the repo, restore the
environment with:

```bash
cd /path/to/dkg-phd-thesis
Rscript -e "renv::restore()"
```

Key R packages used (installed automatically via renv):

- `simr` -- Monte Carlo power simulations for mixed models
- `lme4` -- Linear mixed-effects model fitting
- `furrr` / `future` -- Parallel execution across the parameter grid
- `parallelly` -- Safe core detection
- `RhpcBLASctl` -- BLAS thread pinning to prevent oversubscription
- `argparse` -- Named command-line argument parsing
- `dplyr`, `tidyr`, `tibble` -- Data manipulation
- `tictoc` -- Per-run elapsed time tracking
- `readr` -- Output serialization (.rds, .csv)
- `yaml`, `glue` -- Configuration loading and string formatting

# Configuration

The program uses YAML configuration files in `configs/` to define the parameter
space. Two configurations are provided:

**`run_power_analysis.dev.yaml`** -- A minimal grid for development and testing.
Uses a small number of Level 2 sample sizes, single effect size values, and a
low simulation count (10). Runs in seconds.

**`run_power_analysis.prod.yaml`** -- The full factorial grid used for the
dissertation. Crosses 5 Level 2 sample sizes with 3 values each for Level 1
effect size, Level 2 effect size, cross-level effect size, ICC, and random
slope variance, yielding 1,215 parameter combinations at 1,000 simulations
each.

Configuration parameters:

| Parameter         | Description                                            |
| ----------------- | ------------------------------------------------------ |
| `max_cores`       | Max parallel workers (NULL = conservative default)     |
| `n_lvl1`          | Level 1 sample sizes (repeated measures)               |
| `n_lvl2`          | Level 2 sample sizes (individuals)                     |
| `lvl1_effect_std` | Standardized L1 direct effect sizes                    |
| `lvl2_effect_std` | Standardized L2 direct effect sizes                    |
| `xlvl_effect_std` | Standardized cross-level interaction effect sizes      |
| `icc`             | Intraclass correlation coefficient values              |
| `rand_slope_std`  | Standardized random slope variance values              |
| `alpha`           | Significance level                                     |
| `use_REML`        | Use REML estimation (TRUE/FALSE)                       |
| `n_sims`          | Number of simulations per parameter combination        |
| `verbose`         | Print per-simulation output (FALSE for production)     |
| `return_df`       | Return results as data frame (TRUE for grid runner)    |
| `rand_seed`       | Base random seed (each combination gets seed + run_id) |

# Usage

From the project root directory:

```bash
# Development run (small grid, fast)
bash analysis/run_power_analysis/main.sh dev

# Production run (full grid, hours-long)
bash analysis/run_power_analysis/main.sh prod

# Background a long-running production run
nohup bash analysis/run_power_analysis/main.sh prod &
```

The program automatically:

1. Creates a timestamped log file in `logs/`
2. Activates the `renv` environment via the project-root `.Rprofile`
3. Resolves all paths from the script's filesystem location
4. Loads the configuration for the specified version
5. Builds the parameter grid and reports its size
6. Logs system information (OS, cores, memory)
7. Distributes simulations across available cores
8. Reports success/failure counts and a sample of results
9. Saves timestamped `.rds` and `.csv` output to `data/`

# Output

Each run produces three artifacts:

**Log file** (`logs/run_power_analysis_YYYYMMDD_HHMMSS.log`): Complete
timestamped output including configuration details, system info, simulation
progress, results summary, and wall-clock time.

**RDS file** (`data/power_analysis_results_YYYYMMDD_HHMMSS.rds`): Full results
as an R data frame, including the `simr` result metadata. Suitable for further
analysis in R.

**CSV file** (`data/power_analysis_results_YYYYMMDD_HHMMSS.csv`): Same results
in CSV format for portability.

The results data frame contains one row per effect per parameter combination
(e.g., 1,215 combinations x 3 effects = 3,645 rows for the production config):

| Column                    | Description                                                 |
| ------------------------- | ----------------------------------------------------------- |
| `Effect`                  | Effect type (L1_Direct, L2_Direct, Cross_Level_Interaction) |
| `Power`                   | Estimated power (0-1)                                       |
| `Lower_CI`                | Lower bound of 95% confidence interval                      |
| `Upper_CI`                | Upper bound of 95% confidence interval                      |
| `N_Level1`                | Level 1 sample size for this combination                    |
| `N_Level2`                | Level 2 sample size for this combination                    |
| `Level1_Effect_Std`       | Standardized L1 effect size                                 |
| `Level2_Effect_Std`       | Standardized L2 effect size                                 |
| `XLevel_Intxn_Effect_Std` | Standardized cross-level effect size                        |
| `ICC`                     | Intraclass correlation coefficient                          |
| `Random_Slope_Std`        | Random slope variance                                       |
| `Alpha`                   | Significance level                                          |
| `N_Sims`                  | Number of simulations                                       |
| `run_id`                  | Parameter combination identifier                            |
| `elapsed_time`            | Seconds elapsed for this combination                        |
| `success`                 | Whether the simulation completed without error              |

Power > 0.80 is conventionally interpreted as adequate statistical power.

# Troubleshooting

<details>
<summary>Long-running processes</summary>

The production configuration produces a 1,215-cell parameter matrix. With
1,000 simulations per cell, total runtime depends heavily on available cores.

Reference benchmarks:

| System             | Cores Used | Wall-Clock Time |
| ------------------ | ---------- | --------------- |
| MacBook Pro M1 Max | 6 of 10    | ~18.5 hours     |

Runtime scales roughly inversely with core count. A compute-optimized cloud VM
(e.g., GCP `c2d-highcpu-56` with 56 vCPUs) could reduce this to 2-5 hours.
Set `max_cores` in the prod config to match the VM's vCPU count minus 2.

The program logs system info at startup so you can verify core allocation.
</details>

<details>
<summary>Singular fit warnings</summary>

Messages like `boundary (singular) fit: see help('isSingular')` are normal.
They come from `lme4` when a simulated dataset produces near-zero variance
components. This is expected in Monte Carlo simulations, especially with
smaller Level 2 sample sizes or low ICC values. These warnings do not indicate
a problem with the analysis and do not affect the power estimates.
</details>

<details>
<summary>renv not activating</summary>

The `renv` environment activates automatically via the `.Rprofile` at the
project root. If packages are missing:

```bash
cd /path/to/dkg-phd-thesis
Rscript -e "renv::status()"   # Check for out-of-sync packages
Rscript -e "renv::restore()"  # Install missing packages from lockfile
```

If `renv` itself is not installed, R will attempt to bootstrap it from the
`renv/activate.R` script on first run.
</details>

<details>
<summary>Install or update R on Linux (Ubuntu)</summary>

```bash
wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc \
    | sudo tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc

sudo add-apt-repository \
    "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/"

sudo apt update
sudo apt install r-base
```
</details>

<details>
<summary>Linux kernel disk space issues</summary>

If `/boot` is full (common on long-lived Ubuntu VMs), old kernel images may
need cleanup:

```bash
# Check which kernel is running (do NOT remove this one)
uname -r

# List installed kernel images
dpkg --list | grep linux-image

# Remove packages with "rc" status (removed but config files remain)
sudo apt purge $(dpkg -l | awk '/^rc/ {print $2}')

# Clean up remaining dependencies
sudo apt autoremove --purge

# Verify boot space
df -h /boot
```
</details>

# Contributing

Contributions are welcome. If you have suggestions for improvements or find
bugs, please open an issue or submit a pull request. For questions or
assistance, reach out via [email](mailto:dkgreen.iopsych@gmail.com) or through
the project's [GitHub repository](https://github.com/datasci-iopsy/dkg-phd-thesis).
