# analysis/CLAUDE.md

R (4.4, renv) analysis pipeline. Two active pillars:
- `run_power_analysis/` — multilevel power simulations (Arend & Schafer 2019)
- `run_synthetic_data/` — test/synthetic ESM data generation

Shared utilities in `analysis/shared/utils/common_utils.r`.

## Commands

```bash
Rscript -e "renv::restore()"                               # restore packages from renv.lock
make renv_snapshot                                         # update renv.lock (sanctioned path)
bash run_power_analysis/main.sh dev                        # dev grid (seconds)
bash run_power_analysis/main.sh prod                       # full grid (hours)
bash run_power_analysis/main.sh benchmark_gcp              # GCP timing probe
bash run_power_analysis/main.sh prod_gcp                   # GCP full grid (3,645 cells)
bash analysis/tests/validate_r_structure.sh                # pre-flight; run from project root
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
  - **Visuals**: always use SVG as the output for visuals never PDFs unless explicitly directed

## SQL (sqlfmt)

- Line length: 120 chars (configured in root `pyproject.toml`)
- Format before committing: `poetry run sqlfmt .` (run from project root)

## Variable naming

- L1 time-varying (within-person centered): `VAR.WP` — e.g. `BURN.PHY.WP`
- L2 time-invariant (grand-mean centered): `VAR.BP` — e.g. `PSYK.BR`
- Never mix centering levels in a single model term

## renv freeze

`renv.lock` is frozen. In interactive R sessions, `renv::snapshot()` and `renv::update()` will error unless explicitly opted in. `renv::restore()` is unaffected.

- **Sanctioned snapshot path**: `make renv_snapshot` (sets `RENV_ALLOW_SNAPSHOT=1` automatically)
- **Manual opt-in**: `Sys.setenv(RENV_ALLOW_SNAPSHOT = "1"); renv::snapshot()`
- **Commit the lock update**: `ALLOW_LOCK_COMMIT=1 git commit`

## GCP VM workflow

For large grids, provision a GCP Compute Engine VM via `manage_compute.py`:
1. `python gcp/deploy/manage_compute.py setup` — creates VM + `gcp/deploy/setup_gcp_vm.sh`
2. SSH in, run `make power_analysis_gcp_prod` (or `benchmark_gcp` first to calibrate)
3. `python gcp/deploy/manage_compute.py scp` — download results
4. `python gcp/deploy/manage_compute.py teardown` — delete VM

Machine type and zone are configured in `gcp/deploy/compute.yaml`.

## Worktree notes

- `renv.lock` is frozen — do not run `renv::snapshot()` in a worktree session without opt-in
- Run `renv::restore()` once per worktree checkout; it is unaffected by the freeze guard
- Simulation output (`data/`) is gitignored; each worktree produces independent output
