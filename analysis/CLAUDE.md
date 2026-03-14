# analysis/CLAUDE.md

R (4.4, renv) analysis pipeline. Two active pillars:
- `run_power_analysis/` — multilevel power simulations (Arend & Schafer 2019)
- `run_synthetic_data/` — test/synthetic ESM data generation

Shared utilities in `analysis/shared/utils/common_utils.r`.

## Commands

```bash
Rscript -e "renv::restore()"                               # restore packages from renv.lock
bash run_power_analysis/main.sh dev                        # dev grid (seconds)
bash run_power_analysis/main.sh prod                       # full grid (hours)
cd analysis/tests && bash validate_r_structure.sh          # pre-flight; cd required (script uses cd ../../)
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

## Worktree notes

- `renv.lock` is shared — run `renv::restore()` once per worktree checkout, not repeatedly
- Simulation output (`data/`) is gitignored; each worktree produces independent output
- Never run `main.sh prod` from a worktree without confirming the output path won't collide with main
