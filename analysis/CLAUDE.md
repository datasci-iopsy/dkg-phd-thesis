# analysis/CLAUDE.md

R (4.4, renv) analysis pipeline. Two pillars:
- `run_power_analysis/` — multilevel sensitivity analysis (Arend & Schafer 2019); see `run_power_analysis/README.md`
- `run_synthetic_data/` — synthetic ESM data generation (Python + R + SQL + bash)

Shared utilities in `analysis/shared/utils/`:
- `common_utils.r` — `log_msg()`, `load_config()`, `ensure_dir()`, `get_system_info()`
- `mlm_utils.r` — multilevel model helpers
- `plot_utils.r` — ggplot2 theme and palette utilities

## Commands

Run from project root:

```bash
Rscript -e "renv::restore()"                                           # restore from renv.lock
make renv_snapshot                                                      # update renv.lock (sanctioned)
bash analysis/run_power_analysis/main.sh dev                           # dev grid (seconds)
bash analysis/run_power_analysis/main.sh prod                          # full local grid (hours)
bash analysis/run_power_analysis/main.sh benchmark_gcp                 # GCP timing probe (prod ~= benchmark x 100)
bash analysis/run_power_analysis/main.sh prod_gcp                      # GCP full grid (3,645 cells)
Rscript analysis/run_power_analysis/scripts/visualize_power_analysis.R # SVG figures from latest results
bash analysis/tests/validate_r_structure.sh                            # pre-flight static validation
```

## R conventions

- **Pipe**: native `|>` only — never `%>%`
- **Functions**: `snake_case`; document with `#' @param` / `#' @return` roxygen style
- **Section headers**: `# [1] Section Name ---` numbered, consistent depth
- **Path resolution**: always resolve from script location — never rely on working directory
- **Config**: load via `load_config()` from `common_utils.r`; values at `config$params$*`
- **Logging**: `log_msg()` only — never bare `print()` or `cat()` in scripts
- **Parallel**: `furrr::future_map_dfr()` with `tryCatch()` wrappers in the mapping function
- **Output**: timestamp filenames; write `.rds` + `.csv` pairs; figures as SVG (never PDF)

## Variable naming

- L1 time-varying (within-person centered): `VAR.WP` — e.g. `BURN.PHY.WP`
- L2 time-invariant (grand-mean centered): `VAR.BP` — e.g. `PSYK.BR`
- Never mix centering levels in a single model term

## renv freeze

`renv.lock` is frozen. In interactive R sessions, `renv::snapshot()` and `renv::update()` error unless opted in. `renv::restore()` is unaffected.

- **Sanctioned path**: `make renv_snapshot` (sets `RENV_ALLOW_SNAPSHOT=1`)
- **Manual opt-in**: `Sys.setenv(RENV_ALLOW_SNAPSHOT = "1"); renv::snapshot()`
- **Commit**: `ALLOW_LOCK_COMMIT=1 git commit`
- **Worktrees**: run `renv::restore()` once per checkout; `data/` output is gitignored per worktree
