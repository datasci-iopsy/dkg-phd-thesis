# CLAUDE.md

PhD dissertation: within-person fluctuation in burnout, need frustration, and turnover intentions.
Three pillars: `gcp/` (Python GCP pipeline), `analysis/run_power_analysis/` (R simulations), `analysis/run_synthetic_data/` (test data).
Python >=3.12,<3.13 (Poetry) and R >= 4.4 (renv) managed separately. See `gcp/CLAUDE.md` and `analysis/CLAUDE.md` for domain specifics.

## Makefile

`make help` — primary user-facing interface for all commands (analysis, Python dev, GCP).
`make help_gcp` — GCP deployment detail. Raw commands below are still authoritative for Claude.

## Commands

```bash
# Python
poetry install --with fn-qualtrics-scheduling,fn-intake-confirmation,fn-followup-scheduling,dev
poetry run ruff check . && poetry run ruff format .
poetry run sqlfmt .
poetry run pytest gcp/tests/ -v

# R
Rscript -e "renv::restore()"
bash analysis/run_power_analysis/main.sh dev            # seconds
bash analysis/run_power_analysis/main.sh prod           # full local grid (hours)
bash analysis/run_power_analysis/main.sh benchmark_gcp  # GCP timing probe
bash analysis/run_power_analysis/main.sh prod_gcp       # GCP full grid (3,645 cells)
bash analysis/tests/validate_r_structure.sh             # pre-flight; run from project root

# GCP VM bootstrap (run once on a fresh VM after manage_compute.py setup)
bash setup_gcp_vm.sh

# Deploy (from project root, never from a worktree)
python gcp/deploy/manage_functions.py dev <function-name>      # local dev server on :8080
python gcp/deploy/manage_functions.py deploy <function-name>   # deploy to GCP
python gcp/deploy/manage_infra.py setup|teardown               # BigQuery tables
python gcp/deploy/manage_gateway.py setup|test|teardown        # API Gateway
python gcp/deploy/manage_pubsub.py setup|teardown              # Pub/Sub topics
python gcp/deploy/manage_compute.py setup|status|ssh|scp|teardown  # Compute Engine VM
```

## GCP pipeline

Three Cloud Run functions in an async chain via Pub/Sub:

1. **`run_qualtrics_scheduling`** (HTTP) — Qualtrics webhook POST → Pydantic validation (`WebServicePayload`) → BigQuery `intake_raw` → publishes `IntakeProcessedMessage`
2. **`run_intake_confirmation`** (Pub/Sub) — idempotency check → Twilio SMS → sets `_processed=TRUE` → publishes `FollowupSchedulingMessage`
3. **`run_followup_scheduling`** (Pub/Sub) — idempotency check → builds 3 survey URLs → schedules 3 SMS via Twilio Message Scheduling API → writes SIDs to BigQuery

API Gateway fronts function 1 (university org policy requires auth); validates `x-api-key`, injects IAM JWT.

**Key patterns:**
- **Schema source of truth**: `WebServicePayload` in `models/qualtrics.py` → BQ schema auto-generated via `gcp/shared/utils/bq_schemas.py`. Change models first; schema follows. Then update `web_service_payload.json` fixture and `test_models.py`.
- **Config loading**: each function's `configs/` dir has YAMLs merged alphabetically by `config_loader.py`, validated against Pydantic `AppConfig`. Optional sections (`qualtrics`, `pubsub`, `followup_surveys`) omitted by functions that don't use them.
- **Dependency groups**: `main` (shared), `fn-qualtrics-scheduling`, `fn-intake-confirmation`, `fn-followup-scheduling`, `dev`. Deploy exports `main` + function group to `requirements.txt`.
- **Idempotency**: function 2 checks `_processed` flag; function 3 checks `scheduled_followups` table.
- **Lazy imports**: Twilio and google-cloud-pubsub only loaded in publishing/sending functions.
- **Followup timezone handling**: participant local time → UTC via `zoneinfo.ZoneInfo`; 16-min lead-time guard; past slots skipped. `send_immediately=True` (via `manage_gateway.py test --now`) bypasses fixed times and schedules at now+16/32/48 min for rapid end-to-end testing.

## Power analysis

`main.sh` → `scripts/run_power_analysis.r` → parallel via `furrr::future_map_dfr()`.
Implements Arend & Schafer (2019): variance components → unstandardized effects → `simr::makeLmer()` → `simr::powerSim()` with Kenward-Roger tests.
Dev: 9 combos x 10 sims. Prod (local): 1,215 combos x 1,000 sims. GCP prod: 3,645 cells x 1,000 sims on a `c3-highcpu-176` (174 workers). Output: timestamped `.rds` + `.csv` in `data/`.
GCP VM lifecycle: `manage_compute.py setup` → SSH + run → `scp` results → `teardown`.

## Verification

After Python changes: `poetry run pytest gcp/tests/ -v` → `ruff check . && ruff format --check .` → `sqlfmt --check .`
After R changes: `bash analysis/tests/validate_r_structure.sh`
Schema changes: `models/qualtrics.py` → `bq_schemas.py` → `web_service_payload.json` → `test_models.py` → `manage_infra.py teardown/setup`

## Workflow

- Use Plan mode for complex or multi-file tasks; iterate before implementing
- Break large changes into reviewable chunks
- **Worktrees**: safe for all code edits, tests, and R simulations — never run deploy commands from a worktree
- When working across a worktree + main session simultaneously, coordinate schema changes through main only
