# run_power_analysis

Author & Maintainer: Demetrius K. Green ([Email](mailto:dkgreen.iopsych@gmail.com) | [GitHub](https://github.com/datasci-iopsy) | [LinkedIn](https://www.linkedin.com/in/dkgreen-io/))

Simulation-based sensitivity analysis for two-level (multilevel) models, following the Arend & Schafer (2019) framework. Evaluates statistical power across a fully customizable parameter grid using Monte Carlo simulations via `simr` with Kenward-Roger tests.

- [run\_power\_analysis](#run_power_analysis)
  - [Overview](#overview)
  - [Directory structure](#directory-structure)
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

## Directory structure

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
      power_analysis_utils.r          # Simulation engine (Arend & Schafer)
    main.sh                           # Thin bash wrapper
    README.md                         # This file
  shared/
    utils/
      common_utils.r                  # Shared utilities (logging, config, etc.)
  tests/
    validate_r_structure.sh           # Static pre-flight validation
```

The `data/`, `logs/`, and `figs/` directories are created automatically at runtime and should be listed in `.gitignore`.

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
- `R >= 4.2.0`
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

The program uses YAML configuration files in [`configs/`](configs/) to define the parameter space. Two configurations are provided:

**[`run_power_analysis.dev.yaml`](configs/run_power_analysis.dev.yaml)**: A minimal grid for development and testing. Uses a small number of Level 2 sample sizes, single values for all effect sizes, and a low simulation count (10). Runs in seconds.

**[`run_power_analysis.prod.yaml`](configs/run_power_analysis.prod.yaml)**: The full factorial grid used for the dissertation. Crosses 5 Level 2 sample sizes (200-1000) with 3 values each for Level 1 effect size, Level 2 effect size, cross-level effect size, ICC, and random slope variance, yielding 1,215 parameter combinations at 1,000 simulations each.

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

**Parallel execution.** The `max_cores` parameter caps parallel workers. If NULL, the program defaults to `min(4, available_cores - 4)`. If set, it is capped at `available_cores - 2`. BLAS threads are pinned to 1 per worker via `RhpcBLASctl` to prevent oversubscription.

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
```

### What happens at runtime

1. `main.sh` creates a timestamped log file in `logs/` and starts the wall-clock timer.
2. `main.sh` hands off to `Rscript run_power_analysis.r --version <dev|prod>`.
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

## Static validation

A pre-flight validation script checks directory structure, file presence, path resolution logic, configuration parsing, and R syntax without requiring any R packages to be installed. Run it from the `analysis/tests/` directory:

```bash
bash analysis/tests/validate_r_structure.sh
```

The script reports PASS/FAIL/WARN for each check and exits with a non-zero code if any failures are found. Run this before committing changes or starting a long production run to catch structural issues early.

## Troubleshooting

<details>
<summary>Long-running processes</summary>

The production configuration produces a 1,215-cell parameter matrix. With 1,000 simulations per cell, total runtime depends heavily on available cores.

Reference benchmarks:

| System             | Cores Used | Wall-Clock Time |
| ------------------ | ---------- | --------------- |
| MacBook Pro M1 Max | 6 of 10    | ~18.5 hours     |

Runtime scales roughly inversely with core count. A compute-optimized cloud VM (e.g., GCP `c2d-highcpu-56` with 56 vCPUs) could reduce this to 2-5 hours. Set `max_cores` in the prod config to match the VM's vCPU count minus 2.

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

## Contributing

Contributions are welcome. If you have suggestions for improvements or find bugs, please open an issue or submit a pull request. For questions or assistance, reach out via [email](mailto:dkgreen.iopsych@gmail.com) or through the project's [GitHub repository](https://github.com/datasci-iopsy/dkg-phd-thesis).