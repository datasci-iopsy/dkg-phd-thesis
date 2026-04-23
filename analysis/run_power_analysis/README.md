# run_power_analysis

Author & Maintainer: Demetrius K. Green ([Email](mailto:dkgreen.iopsych@gmail.com) | [GitHub](https://github.com/datasci-iopsy) | [LinkedIn](https://www.linkedin.com/in/dkgreen-io/))

Simulation-based sensitivity analysis for two-level (multilevel) models, following the Arend & Schafer (2019) framework. Evaluates statistical power across a fully customizable parameter grid using Monte Carlo simulations via `simr` with Kenward-Roger tests.

- [run\_power\_analysis](#run_power_analysis)
  - [Overview](#overview)
  - [How it works](#how-it-works)
  - [Requirements](#requirements)
    - [OS compatibility](#os-compatibility)
    - [System requirements](#system-requirements)
    - [R packages](#r-packages)
  - [Configuration](#configuration)
  - [Usage](#usage)
    - [Running the program](#running-the-program)
    - [What happens at runtime](#what-happens-at-runtime)
  - [Output](#output)
  - [Static validation](#static-validation)
  - [Troubleshooting](#troubleshooting)
  - [Contributing](#contributing)

## Overview

This program answers a core dissertation design question: given 3 repeated measures (Level 1) nested within N participants (Level 2), what sample size is needed to detect effects of various magnitudes with adequate statistical power (> 0.80)?

Rather than solving a closed-form equation, it uses Monte Carlo simulation to empirically estimate power for every combination of parameters in a configurable grid. Three fixed effects are evaluated per combination: Level 1 direct, Level 2 direct, and cross-level interaction.

The program builds a full factorial grid from configuration parameters, distributes the grid across parallel workers via `furrr`, and saves timestamped results. It is designed to run from the command line, eliminating the need for IDEs (e.g., RStudio, VS Code).

The architecture follows a thin-wrapper pattern: [`main.sh`](main.sh) handles process lifecycle (log file creation, wall-clock timing), while [`run_power_analysis.r`](scripts/run_power_analysis.r) owns all application logic (path resolution, configuration, renv activation, parallel execution, and output).

Key entry points: [`main.sh`](main.sh) (bash wrapper), [`scripts/run_power_analysis.r`](scripts/run_power_analysis.r) (orchestrator), and [`scripts/visualize_power_analysis.R`](scripts/visualize_power_analysis.R) (visualization). The visualizer auto-detects the most recent results file, produces SVG power curve figures saved to `figs/`, and scales from dev to prod grids without changes. The simulation engine lives in [`utils/power_analysis_utils.r`](utils/power_analysis_utils.r). Runtime directories (`data/`, `logs/`, `figs/`) are created automatically and gitignored.

## How it works

The simulation engine ([`power_analysis_utils.r`](utils/power_analysis_utils.r)) implements the Arend & Schafer (2019) procedure for each parameter combination in the grid. The process has five steps.

**Step 1: Derive variance components.** Starting from standardized inputs (ICC, standardized effect sizes, random slope variance), the function computes unconditional and conditional variance components using Arend & Schafer's equations 10-11. Unconditional Level 1 variance is fixed at 1.00 as the standardization anchor. Level 2 unconditional variance is derived from the ICC as `icc / (1 - icc)`. Conditional variances account for the variance explained by each predictor.

**Step 2: Compute population effects.** Standardized effect sizes are converted to unstandardized (population) values using equation 15: each standardized effect is multiplied by the square root of the corresponding unconditional variance.

**Step 3: Build a population model.** A synthetic data structure is created with `n_lvl1` repeated measures crossed with `n_lvl2` individuals. `simr::makeLmer()` constructs a population-level mixed model (`y ~ x * Z + (x | g)`) from the derived fixed effects, random effects covariance matrix, and residual standard deviation.

**Step 4: Run Monte Carlo power simulations.** For each of three fixed effects (L1 direct effect of `x`, L2 direct effect of `Z`, cross-level interaction `x:Z`), `simr::powerSim()` generates `n_sims` datasets from the population model, fits the mixed model to each, and tests significance using Kenward-Roger. Power is the proportion of simulations that reject the null.

**Step 5: Return results.** Each combination produces power estimates with 95% confidence intervals for all three effects. The grid runner ([`run_power_analysis.r`](scripts/run_power_analysis.r)) collects these into a single data frame with full parameter context, timing, and success/failure status.

## Requirements

### OS compatibility

**macOS**: Fully tested and supported.

**Linux (Ubuntu)**: Fully tested and supported. Other distros (Debian, RHEL/CentOS) may require additional configuration.

**Windows**: Not supported. The parallel backend uses `future::plan(multicore)` on Unix and falls back to `multisession` on Windows, but the bash wrapper and overall pipeline are not tested on Windows.

### System requirements

- `bash` (any modern version; developed on 5.x)
- `R >= 4.4.0`
- `Python` (required by the `argparse` R package via `findpython`)

### R packages

All R package dependencies are managed by `renv`. The [`renv.lock`](../../renv.lock) file at the project root pins exact package versions. After cloning the repo, restore the environment with:

```bash
cd /path/to/dkg-phd-thesis
Rscript -e "renv::restore()"
```

Key R packages (installed automatically via `renv`):

- `simr`: Monte Carlo power simulations for mixed models
- `lme4`: Linear mixed-effects model fitting
- `furrr` / `future`: Parallel execution across the parameter grid
- `parallelly`: Safe core detection
- `RhpcBLASctl`: BLAS thread pinning to prevent oversubscription
- `argparse`: Named command-line argument parsing
- `dplyr`, `tidyr`, `tibble`: Data manipulation
- `tictoc`: Per-run elapsed time tracking
- `readr`: Output serialization (.rds, .csv)
- `yaml`, `glue`: Configuration loading and string formatting

## Configuration

The program uses YAML configuration files in [`configs/`](configs/) to define the parameter space. Four configurations are provided:

**[`run_power_analysis.dev.yaml`](configs/run_power_analysis.dev.yaml)**: A minimal grid for development and testing. 3 Level 2 sample sizes with single values for all effect sizes, yielding **3 combinations at 10 simulations each**. Runs in seconds.

**[`run_power_analysis.prod.yaml`](configs/run_power_analysis.prod.yaml)**: The full factorial grid used for the dissertation. Crosses 5 Level 2 sample sizes (200-1000) with 3 values each for Level 1 effect size, Level 2 effect size, cross-level effect size, ICC, and random slope variance, yielding **1,215 combinations at 1,000 simulations each**.

**[`run_power_analysis.benchmark_gcp.yaml`](configs/run_power_analysis.benchmark_gcp.yaml)**: A timing probe for any VM. Uses the full effect-size grid with 3 Level 2 sizes, yielding **729 combinations at 50 simulations each**. Uses auto-detected workers. Run this first on a new VM to calibrate expected runtime: `prod_min ≈ benchmark_min × 100` (the benchmark grid is 100× smaller than prod_gcp -- 729 cells × 50 sims vs 3,645 cells × 1,000 sims -- at the same worker count).

**[`run_power_analysis.prod_gcp.yaml`](configs/run_power_analysis.prod_gcp.yaml)**: The expanded GCP grid. Crosses 15 Level 2 sample sizes (100-1500 by 100) with the same effect-size grid as prod, yielding **3,645 combinations at 1,000 simulations each**. Auto-detects workers on any instance; on a `c3-highcpu-176` this yields 174 workers (176 vCPUs - 2).

| Parameter         | Description                                            |
| ----------------- | ------------------------------------------------------ |
| `max_cores`       | Max parallel workers (NULL = auto-detect: `available_cores - 2`, floor 1) |
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

**Parallel execution.** The `max_cores` parameter caps parallel workers. If NULL, the program defaults to `available_cores - 2` (floor of 1), using all available capacity. If set, it is capped at `available_cores - 2`. BLAS threads are pinned to 1 per worker via `RhpcBLASctl` to prevent oversubscription.

**Reproducibility.** Each parameter combination receives a unique seed derived from `rand_seed + run_id`, where `run_id` is the row number in the factorial grid. This ensures reproducibility while avoiding seed collisions across combinations.

## Usage

### Running the program

All commands are run from the project root directory.

```bash
# Development run (small grid, fast: seconds)
bash analysis/run_power_analysis/main.sh dev

# Production run (full grid: hours)
bash analysis/run_power_analysis/main.sh prod

# Background a long-running production run
nohup bash analysis/run_power_analysis/main.sh prod &

# GCP VM: benchmark first, then full grid
bash analysis/run_power_analysis/main.sh benchmark_gcp
nohup bash analysis/run_power_analysis/main.sh prod_gcp &
```

### What happens at runtime

1. `main.sh` creates a timestamped log file in `logs/` and starts the wall-clock timer.
2. `main.sh` hands off to `Rscript run_power_analysis.r --version <dev|prod|benchmark_gcp|prod_gcp>`.
3. The R script activates `renv` via the project-root [`.Rprofile`](../../.Rprofile), resolves all paths from its own filesystem location, and loads the version-specific configuration.
4. A full factorial parameter grid is built via `tidyr::expand_grid()` and its size is logged.
5. System information (OS, cores, memory) is logged.
6. The grid is distributed across parallel workers via `furrr::future_map_dfr()`. Each combination runs the simulation engine with per-run error handling and timing.
7. Results are collected. Success/failure counts and a sample of results are printed.
8. Timestamped `.rds` and `.csv` files are saved to `data/`.
9. `main.sh` reports total wall-clock time.

## Output

Each run produces three artifacts:

**Log file** (`logs/run_power_analysis_YYYYMMDD_HHMMSS.log`): Complete timestamped output including configuration details, system info, simulation progress, results summary, and wall-clock time.

**RDS file** (`data/power_analysis_results_YYYYMMDD_HHMMSS.rds`): Full results as an R data frame. Suitable for further analysis in R.

**CSV file** (`data/power_analysis_results_YYYYMMDD_HHMMSS.csv`): Same results in CSV format for portability.

The results data frame contains one row per effect per parameter combination (e.g., 1,215 combinations x 3 effects = 3,645 rows for the production config):

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

**Figures** (`figs/`): Power curve visualizations can be generated from the results data using the visualization script. Figures are saved to `figs/` and are gitignored.

## Static validation

A pre-flight validation script checks directory structure, file presence, path resolution logic, configuration parsing, and R syntax without requiring any R packages to be installed. Run from the project root directory:

```bash
bash analysis/tests/validate_r_structure.sh
```

The script reports PASS/FAIL/WARN for each check and exits with a non-zero code if any failures are found. Run this before committing changes or starting a long production run to catch structural issues early.

## Troubleshooting

<details>
<summary>Long-running processes</summary>

Total runtime depends heavily on available cores and grid size.

Reference benchmarks:

| Config    | System                   | Grid     | Cores Used | Wall-Clock Time |
| --------- | ------------------------ | -------- | ---------- | --------------- |
| `prod`    | MacBook Pro M1 Max       | 1,215    | 6 of 10    | ~18.5 hours     |
| `prod_gcp`| GCP `c3-highcpu-176`     | 3,645    | 174 of 176 | ~7 hours 10 min |

Runtime scales roughly inversely with core count. Use `benchmark_gcp` to calibrate on a new VM: `prod_min ≈ benchmark_min × 100` (the benchmark runs 729 cells × 50 sims; prod_gcp runs 3,645 cells × 1,000 sims -- a 100× difference -- at the same auto-detected worker count). Core count is auto-detected (`available_cores - 2`); hardcode `max_cores` in the config only to override.

The program logs system info at startup so you can verify core allocation.
</details>

<details>
<summary>Singular fit warnings</summary>

Messages like `boundary (singular) fit: see help('isSingular')` are normal. They come from `lme4` when a simulated dataset produces near-zero variance components. This is expected in Monte Carlo simulations, especially with smaller Level 2 sample sizes or low ICC values. These warnings do not indicate a problem with the analysis and do not affect the power estimates.
</details>

<details>
<summary>renv not activating</summary>

The `renv` environment activates automatically via the [`.Rprofile`](../../.Rprofile) at the project root. If packages are missing:

```bash
cd /path/to/dkg-phd-thesis
Rscript -e "renv::status()"   # Check for out-of-sync packages
Rscript -e "renv::restore()"  # Install missing packages from lockfile
```

If `renv` itself is not installed, R will attempt to bootstrap it from the `renv/activate.R` script on first run.
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

If `/boot` is full (common on long-lived Ubuntu VMs), old kernel images may need cleanup:

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

<details>
<summary>University HPC / shared server limitations</summary>

This analysis was originally developed to run on university HPC infrastructure. In practice, several issues made this impractical:

- **R version pinning**: University-managed R installations were often below 4.4, and users lacked permissions to install or upgrade system-wide R. Building R from source required compiler toolchains that were also restricted.
- **Library compilation failures**: Packages like `lme4`, `RhpcBLASctl`, and `simr` depend on system libraries (`liblapack`, `libopenblas`, `libcurl`) that were missing or outdated. Without `sudo` access, installing these dependencies required coordination with IT.
- **Job scheduler constraints**: HPC batch schedulers (e.g., SLURM) added overhead for iterating on configuration. Interactive sessions had time limits that made long-running `prod` grids unreliable.

These issues led to the GCP Compute Engine approach: a fresh Ubuntu VM with full root access, where R and all dependencies can be installed cleanly via [`gcp/deploy/setup_gcp_vm.sh`](../../gcp/deploy/setup_gcp_vm.sh). The `benchmark_gcp` and `prod_gcp` configurations were designed specifically for this workflow.
</details>

<details>
<summary>GCP VM setup and usage</summary>

The `manage_compute.py` script automates VM lifecycle. Typical workflow:

```bash
# 1. Create VM and bootstrap R environment
python gcp/deploy/manage_compute.py setup

# 2. SSH into the VM
python gcp/deploy/manage_compute.py ssh

# 3. On the VM: run benchmark first, then prod
cd dkg-phd-thesis
make power_analysis_gcp_benchmark    # timing probe (~minutes)
nohup make power_analysis_gcp_prod & # full grid in background

# 4. When done, download results
python gcp/deploy/manage_compute.py scp

# 5. Delete the VM to stop billing
python gcp/deploy/manage_compute.py teardown
```

Machine type, zone, and disk size are configured in `gcp/deploy/compute.yaml`. The `c3-highcpu-176` instance provides 176 vCPUs (174 workers after reserving 2 for OS overhead). If capacity is unavailable in one zone, edit `compute.yaml` to try another from the `available_zones` list.
</details>

## Contributing

Contributions are welcome. If you have suggestions for improvements or find bugs, please open an issue or submit a pull request. For questions or assistance, reach out via [email](mailto:dkgreen.iopsych@gmail.com) or through the project's [GitHub repository](https://github.com/datasci-iopsy/dkg-phd-thesis).