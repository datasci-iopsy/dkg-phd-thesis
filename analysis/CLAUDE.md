# analysis/CLAUDE.md

R (4.4, uvr) analysis pipeline. Three pillars:
- `run_power_analysis/` : multilevel sensitivity analysis (Arend & Schafer 2019); see `run_power_analysis/README.md`
- `run_synthetic_data/` : synthetic ESM data generation (Python + R + SQL + bash); analysis pipeline runs in 6 steps starting with `data_quality.r` (careless responding screening)
- `run_study_analysis/` : official study pipeline on real participant data from BigQuery; same 6-step structure; see `run_study_analysis/README.md`

Shared utilities in `analysis/shared/utils/`:
- `common_utils.r` — `log_msg()`, `load_config()`, `ensure_dir()`, `get_system_info()`
- `mlm_utils.r` — multilevel model helpers
- `plot_utils.r` — ggplot2 theme, palette utilities, and save-helper factories (`make_save_fig`, `make_save_tbl`, `make_save_base_svg`)
- `table_utils.r` — flextable/officer helpers for APA Word table generation; formatting functions (`fmt_p`, `fmt_r`, `fmt_est`)

## Commands

Run from project root:

```bash
uvr sync                                                                # restore packages from uvr.lock
uvr lock && ALLOW_LOCK_COMMIT=1 git commit                             # update uvr.lock (sanctioned)
bash analysis/run_power_analysis/main.sh dev                           # dev grid (seconds)
bash analysis/run_power_analysis/main.sh prod                          # full local grid (hours)
bash analysis/run_power_analysis/main.sh benchmark_gcp                 # GCP timing probe (prod ~= benchmark x 100)
bash analysis/run_power_analysis/main.sh prod_gcp                      # GCP full grid (3,645 cells)
uvr run analysis/run_power_analysis/scripts/visualize_power_analysis.r # SVG figures from latest results
bash analysis/tests/validate_r_structure.sh                            # pre-flight static validation
make synthetic_analysis                                                 # steps 1-5; run make synthetic_tables separately for publication output
make synthetic_data_quality                                             # Step 1 only: careless responding screening
make synthetic_tables                                                   # Step 6: publication-ready Word .docx tables
make study_export                                                       # rebuild BQ fact tables and re-export CSVs (prompts for confirmation)
make study_analysis                                                     # steps 1-5 on real study data (requires data/export/ CSVs)
make study_data_quality                                                 # Step 1 only: careless responding screening on study data
make study_tables                                                       # Step 6: publication Word .docx tables (gtsummary + flextable)
```

## Synthetic data quality screening

`run_synthetic_data/scripts/r/data_quality.r` runs before all other synthetic analysis scripts. It must be run first; Steps 2–5 load the cleaned export it produces.

- **L1 indices** (longstring, IRV, Mahalanobis) are computed per survey (3 surveys), not pooled across the within-person observations. This is appropriate for the repeated-measures ESM design.
- **L2 indices** (longstring, IRV, Mahalanobis) are computed once per person on the intake item block.
- **Exclusion**: participants flagged by >= 2 of 6 criteria are removed.
- Thresholds are defined as named constants at the top of the script — adjust there only.
- Output figures are static filenames (overwrite on rerun); diagnostic CSVs are gitignored and regenerated locally.

## File naming

All R scripts use the lowercase `.r` extension throughout this codebase (`data_quality.r`, not `data_quality.R`). This convention is enforced for Linux/GCP workflow compatibility: Linux filesystems are case-sensitive, so `.R` and `.r` are distinct names. macOS is case-insensitive and tolerates either, but the GCP VMs used for production runs are Ubuntu. All new R files must use `.r`. The `scripts/R/` directory name in `run_study_analysis/` is intentionally uppercase (a pre-existing convention for the scripts subdirectory); the scripts inside it are still `.r`.

## R conventions

- **Pipe**: native `|>` only — never `%>%`
- **Functions**: `snake_case`; document with `#' @param` / `#' @return` roxygen style
- **Section headers**: `# [1] Section Name ---` numbered, consistent depth
- **Path resolution**: always resolve from script location — never rely on working directory
- **Config**: load via `load_config()` from `common_utils.r`; values at `config$params$*`
- **Logging**: `log_msg()` only — never bare `print()` or `cat()` in scripts
- **Parallel**: `furrr::future_map_dfr()` with `tryCatch()` wrappers in the mapping function
- **Output**: timestamp filenames for pipeline results; export CSVs use static names (overwrite on rerun); write `.rds` + `.csv` pairs; figures as SVG (never PDF)

## Variable naming

- L1 time-varying (within-person centered): `VAR.WP` — e.g. `BURN.PHY.WP`
- L2 time-invariant (grand-mean centered): `VAR.BP` — e.g. `PSYK.BR`
- Never mix centering levels in a single model term

## uvr

`uvr.lock` is frozen. Pre-commit hook blocks commits staging the lock file.

- **Install/restore**: `uvr sync` — installs packages from `uvr.lock` into `.uvr/library/`
- **Update lock**: `uvr lock` to regenerate, then `ALLOW_LOCK_COMMIT=1 git commit` to commit
- **Worktrees**: run `uvr sync` once per checkout; `data/` output is gitignored per worktree
