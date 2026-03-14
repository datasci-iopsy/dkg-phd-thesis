# CLAUDE.md

PhD dissertation: within-person fluctuation in burnout, need frustration, and turnover intentions.
Three pillars: `gcp/` (Python GCP pipeline), `analysis/run_power_analysis/` (R simulations), `analysis/run_synthetic_data/` (test data).
Python >=3.12,<3.13 (Poetry) and R 4.4 (renv) managed separately.

## Commands

```bash
# Python
poetry install --with fn-qualtrics-scheduling,fn-intake-confirmation,fn-followup-scheduling,dev
poetry run ruff check . && poetry run ruff format .
poetry run sqlfmt .
poetry run pytest gcp/tests/ -v

# R
Rscript -e "renv::restore()"
bash analysis/run_power_analysis/main.sh dev   # seconds; use 'prod' for full grid (hours)
bash analysis/tests/validate_r_structure.sh     # pre-flight check, no R packages needed

# Deploy (from project root)
python gcp/deploy/manage_functions.py dev <function-name>      # local dev server on :8080
python gcp/deploy/manage_functions.py deploy <function-name>   # deploy to GCP
python gcp/deploy/manage_infra.py setup|teardown               # BigQuery tables
python gcp/deploy/manage_gateway.py setup|test|teardown        # API Gateway
python gcp/deploy/manage_pubsub.py setup|teardown              # Pub/Sub topics
```

## GCP pipeline

Three Cloud Run functions in an async chain via Pub/Sub:

1. **`run_qualtrics_scheduling`** (HTTP) — Qualtrics webhook POST → Pydantic validation (`WebServicePayload`) → BigQuery `intake_raw` → publishes `IntakeProcessedMessage`
2. **`run_intake_confirmation`** (Pub/Sub) — idempotency check → Twilio SMS confirmation via `from_number` → sets `_processed=TRUE` → publishes `FollowupSchedulingMessage`
3. **`run_followup_scheduling`** (Pub/Sub) — idempotency check on `scheduled_followups` table → builds 3 survey URLs (9 AM, 1 PM, 5 PM slots) → schedules 3 SMS via Twilio Message Scheduling API (`messaging_service_sid`, `send_at` in UTC) → writes SIDs to BigQuery

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
Dev config: 9 combos x 10 sims. Prod config: 1,215 combos x 1,000 sims.
Output: timestamped `.rds` + `.csv` in `data/`. Shared R utils in `analysis/shared/utils/common_utils.r`.

## Conventions

- **Table naming**: `<purpose>_<stage>` — `intake_raw`, `intake_clean`, `scheduled_followups`
- **Variable naming**: L1 time-varying (`BURN.PHY.WP`), L2 time-invariant (`PSYK.BR`); WP = within-person, BP = grand-mean centered
- **Secrets**: `dkg-twilio-config` JSON blob in Secret Manager → `TWILIO_CONFIG` env var
- **Local dev**: env vars via `.envrc` / direnv; `dev` command prints required secrets
- **Schema changes require BQ table teardown/recreate** (streaming API limitation)
- **All tests mock GCP/Twilio** — no credentials or network needed
- **Deploy config**: `gcp/deploy/functions.yaml` is single source of truth for all functions, SAs, IAM roles, secrets, triggers

## Verification

After Python changes:
- `poetry run pytest gcp/tests/ -v`
- `poetry run ruff check . && poetry run ruff format --check .`
- `poetry run sqlfmt --check .`

After R changes: `bash analysis/tests/validate_r_structure.sh`

For schema changes: update model → regenerate fixture → run tests → teardown/recreate BQ table

## Workflow

- Use Plan mode for complex or multi-file tasks; iterate on plan before implementing
- Break large changes into reviewable chunks
- For schema changes follow the chain: `models/qualtrics.py` → `bq_schemas.py` → `web_service_payload.json` → `test_models.py` → `manage_infra.py teardown/setup`

## Learnings

<!-- Add patterns discovered during development and PR reviews -->
