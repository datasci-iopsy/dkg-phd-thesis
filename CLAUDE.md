# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

PhD dissertation research project on within-person fluctuation in burnout, need frustration, and turnover intentions. The codebase has three main pillars:

1. **`gcp/`** — Python GCP data pipeline (Cloud Run functions, API Gateway, BigQuery, Pub/Sub)
2. **`analysis/run_power_analysis/`** — R power simulation pipeline (Monte Carlo, multilevel models)
3. **`analysis/run_synthetic_data/`** — Synthetic data for testing the pipeline (CSV + BigQuery SQL)

Both Python (Poetry, `>=3.12,<3.13`) and R (`renv`) environments must be managed separately.

## Python environment

```bash
# Install dependencies (all groups)
poetry install --with fn-qualtrics-scheduling,fn-intake-confirmation,dev

# Lint
poetry run ruff check .
poetry run ruff format .

# Format SQL
poetry run sqlfmt .

# Run all GCP tests
poetry run pytest gcp/tests/ -v

# Run tests with coverage
poetry run pytest gcp/tests/ -v \
  --cov=gcp/cloud_run_functions/run_qualtrics_scheduling \
  --cov=gcp/shared/utils \
  --cov-report=term-missing

# Run a single test file
poetry run pytest gcp/tests/test_models.py -v
```

## R environment

```bash
# Restore R packages from lockfile (run once after cloning)
Rscript -e "renv::restore()"

# Or via Make
make renv_restore    # restore packages
make renv_snapshot   # update lockfile after adding packages
make renv_repair     # fix broken cache/symlinks
make renv_status     # check sync state
```

The `renv` environment activates automatically via `.Rprofile` at the project root.

## Power analysis pipeline

```bash
# Development run (small grid, completes in seconds)
bash analysis/run_power_analysis/main.sh dev

# Production run (1,215 combos × 1,000 sims — hours)
nohup bash analysis/run_power_analysis/main.sh prod &

# Or via Make
make power_analysis VERSION=dev
make power_analysis VERSION=prod

# Pre-flight structural validation (no R packages needed)
bash analysis/tests/validate_r_structure.sh
```

## GCP infrastructure CLI

All commands run from the project root:

```bash
# Local dev server (copies shared/ in, starts functions-framework on :8080)
python gcp/deploy/manage_functions.py dev run-qualtrics-scheduling

# Deploy to GCP
python gcp/deploy/manage_functions.py deploy run-qualtrics-scheduling

# BigQuery setup/teardown
python gcp/deploy/manage_infra.py setup
python gcp/deploy/manage_infra.py teardown --force

# API Gateway setup/test/teardown
python gcp/deploy/manage_gateway.py setup
python gcp/deploy/manage_gateway.py test
python gcp/deploy/manage_gateway.py teardown

# Pub/Sub topic lifecycle
python gcp/deploy/manage_pubsub.py setup
python gcp/deploy/manage_pubsub.py teardown
```

## Architecture: GCP pipeline

Two Cloud Run functions connected by Pub/Sub:

- **`run_qualtrics_scheduling`**: Receives Qualtrics Web Service POST → validates with Pydantic (`WebServicePayload`, 34 fields) → writes to BigQuery `intake_raw` → publishes `IntakeProcessedMessage` to Pub/Sub.
- **`run_intake_confirmation`**: Triggered by Pub/Sub/Eventarc → checks BigQuery idempotency flag → sends Twilio SMS → sets `_processed = TRUE`.

The API Gateway sits in front of `run_qualtrics_scheduling` (university org policy prohibits unauthenticated Cloud Run invocations); it validates an `x-api-key` header and injects an IAM JWT.

**Single source of truth for schemas**: The BigQuery schema for `intake_raw` is auto-generated from `WebServicePayload` via `gcp/shared/utils/bq_schemas.py`. When changing the survey schema, update `models/qualtrics.py` first; the BigQuery schema follows automatically. Then update `web_service_payload.json` and `test_models.py` to match.

**Config loading**: Each function has a `configs/` directory. `config_loader.py` merges all YAMLs alphabetically and validates against `AppConfig` (Pydantic). Optional config sections (`qualtrics`, `pubsub`, `secret_manager`) are omitted by functions that don't use them.

**Dependency groups**: `main` (shared), `fn-qualtrics-scheduling`, `fn-intake-confirmation`, `dev`. At deploy time, `manage_functions.py` exports `main` + the function's group to `requirements.txt`.

## Architecture: power analysis

`analysis/run_power_analysis/main.sh` is a thin wrapper — it creates a timestamped log and hands off to `scripts/run_power_analysis.r`. The R script:
1. Activates `renv` via `.Rprofile`
2. Loads version-specific YAML config from `configs/`
3. Builds a full factorial parameter grid (`tidyr::expand_grid`)
4. Distributes across parallel workers (`furrr::future_map_dfr`)
5. Saves timestamped `.rds` and `.csv` to `data/`

The simulation engine in `utils/power_analysis_utils.r` implements Arend & Schafer (2019): derives variance components → computes unstandardized effects → builds population model with `simr::makeLmer()` → runs `simr::powerSim()` with Kenward-Roger tests.

Shared R utilities live in `analysis/shared/utils/common_utils.r`.

## Key conventions

- **BigQuery table naming**: `<purpose>_<stage>` (e.g., `intake_raw`, `intake_clean`, `followup_raw`, `followup_clean`)
- **Variable naming** (dissertation): L1 time-varying (e.g., `BURN.PHY.WP`), L2 time-invariant (e.g., `PSYK.BR`); WP = within-person centered, BP = grand-mean centered
- **Secrets**: Twilio credentials stored as `dkg-twilio-config` in Secret Manager as a JSON blob injected via `TWILIO_CONFIG` env var. Qualtrics secrets are currently commented out of `functions.yaml`.
- **Local dev**: Set env vars via `.envrc` / direnv. The `dev` command in `manage_functions.py` prints any secrets the function expects.
- **Tests mock all GCP calls** — no credentials or network access needed to run `gcp/tests/`.
- **Schema changes require BigQuery table teardown/recreate** (streaming API does not support in-place schema changes).
