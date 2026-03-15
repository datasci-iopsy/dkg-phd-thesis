# analysis/CLAUDE.md

R (>= 4.4, renv) analysis pipeline. Two active pillars:
- `run_power_analysis/` — multilevel power simulations (Arend & Schafer 2019)
- `run_synthetic_data/` — test/synthetic ESM data generation

Shared utilities in `analysis/shared/utils/common_utils.r`.

## Commands

```bash
Rscript -e "renv::restore()"                               # restore packages from renv.lock
bash run_power_analysis/main.sh dev                        # dev grid (seconds)
bash run_power_analysis/main.sh benchmark                  # timing probe before full prod run
bash run_power_analysis/main.sh prod_vm1                   # VM 1: n_lvl2=[100,800,1500]
# prod_vm2–prod_vm5: one per VM for the full 3,645-cell grid (see Linux VM section below)
bash analysis/tests/validate_r_structure.sh                # pre-flight; run from project root
```

## Structure

```
run_power_analysis/
  configs/        # dev.yaml / prod.yaml — sim parameters
  scripts/        # run_power_analysis.r (orchestrator)
  utils/          # power_analysis_utils.r (simulation engine)
  data/           # timestamped .rds + .csv outputs (gitignored)
  figs/           # output figures
run_synthetic_data/
  schemas/        # table schema definitions
  data/import/    # input CSVs (required before running any analysis)
  data/export/    # generated synthetic panel data
  figs/eda/       # EDA output figures
  figs/mlm/       # MLM output figures
  scripts/r/      # analysis scripts — run in this order:
    eda.R               # 1. exploratory data analysis
    correlation.R       # 2. bivariate correlations
    measurement_model.R # 3. CFA / measurement model
    multilevel_model.R  # 4. main MLM analysis (71 KB)
shared/utils/
  common_utils.r  # log_msg(), load_config(), ensure_dir(), get_system_info()
```

## R conventions

- **Pipe**: native `|>` only — never `%>%`
- **Functions**: `snake_case`; document with `#' @param` / `#' @return` roxygen style
- **Section headers**: `# [1] Section Name ---` numbered, consistent depth
- **Path resolution**: always resolve from script location — never rely on working directory
- **Config**: load via `load_config()` from `common_utils.r`; values at `config$params$*`
- **Logging**: use `log_msg()` — never bare `print()` or `cat()` in scripts
- **Parallel**: `furrr::future_map_dfr()` with `tryCatch()` wrappers in the mapping function
- **Output**: always timestamp filenames; write `.rds` + `.csv` pairs

## SQL (sqlfmt)

- Line length: 120 chars (configured in root `pyproject.toml`)
- Format before committing: `poetry run sqlfmt .` (run from project root)

## Variable naming

- L1 time-varying (within-person centered): `VAR.WP` — e.g. `BURN.PHY.WP`
- L2 time-invariant (grand-mean centered): `VAR.BP` — e.g. `PSYK.BR`
- Never mix centering levels in a single model term

## Linux VM (Ubuntu)

Per-VM bootstrap (idempotent — safe to re-run):
```bash
bash clean_linux_distro.sh   # fix /boot space + dpkg state (run first on every university VM)
bash setup_remote.sh         # install R >= 4.4 + renv::restore()
```

5-VM production workflow (one reservation per VM, one config per VM):
```bash
make power_analysis_benchmark          # VM 1 only — timing probe, foreground (~5–20 min)
# review wall-clock time; if per_vm_hours > 6, split to 10 VMs instead
make power_analysis_prod_vm1           # VM 1: n_lvl2=[100,800,1500]
make power_analysis_prod_vm2           # VM 2: n_lvl2=[200,900,1300]
make power_analysis_prod_vm3           # VM 3: n_lvl2=[300,1000,1100]
make power_analysis_prod_vm4           # VM 4: n_lvl2=[400,600,1400]
make power_analysis_prod_vm5           # VM 5: n_lvl2=[500,700,1200]
```
Monitor: `tail -f run_power_analysis/logs/*.log`. Combine outputs:
`dplyr::bind_rows(readRDS("vm1.rds"), ..., readRDS("vm5.rds"))` → 3,645 rows total.

## Worktree notes

- `renv.lock` is shared — run `renv::restore()` once per worktree checkout, not repeatedly
- Simulation output (`data/`) is gitignored; each worktree produces independent output
- Never run prod_vm configs from a worktree — output paths collide with main
- Each university VM reservation is independent; one config per VM is safe
