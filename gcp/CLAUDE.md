# gcp/CLAUDE.md

Python (`>=3.12,<3.13, Poetry`) Cloud Run pipeline. Three async functions chained via Pub/Sub.
All tests mock GCP/Twilio — no credentials or network access needed for local work.

## Commands

```bash
# From project root
poetry run ruff check gcp/ && poetry run ruff format gcp/
poetry run sqlfmt gcp/
poetry run pytest gcp/tests/ -v

# Deploy (never from a worktree)
python gcp/deploy/manage_functions.py dev <fn>      # local dev on :8080
python gcp/deploy/manage_functions.py deploy <fn>   # deploy to GCP
python gcp/deploy/manage_infra.py setup|teardown    # BQ tables
python gcp/deploy/manage_gateway.py setup|teardown  # API Gateway
python gcp/deploy/manage_gateway.py test [--now]    # end-to-end test; --now schedules SMS at now+16/32/48 min
python gcp/deploy/manage_pubsub.py setup|teardown   # Pub/Sub topics

# Compute Engine VM (power analysis)
python gcp/deploy/manage_compute.py setup            # create VM + run setup_gcp_vm.sh
python gcp/deploy/manage_compute.py status           # show VM state + external IP
python gcp/deploy/manage_compute.py ssh              # SSH into VM
python gcp/deploy/manage_compute.py scp              # download results from VM
python gcp/deploy/manage_compute.py teardown         # delete VM (warns if results not downloaded)
```

## Formatting

- **Ruff**: line-length = 80 (configured in root `pyproject.toml`)
- **sqlfmt**: line-length = 120 (configured in root `pyproject.toml`)
- Run `ruff check --fix` to auto-fix before committing; treat all warnings as errors
- Common auto-fixable: F541 bare `f""` strings without placeholders (`--fix` handles them)

## Python conventions

- **Type hints** on all function signatures
- **Pydantic** for all config and payload validation — never parse dicts manually
- **Cold-start config**: load once at module level (`config = load_config(...)`), not inside handlers
- **Lazy imports**: Twilio and `google-cloud-pubsub` imported inside the functions that use them
- **Logging**: `logger = logging.getLogger(__name__)` per module; `logger.info("msg %s", var)` style (not f-strings)
- **Error handling**: try-except at handler boundary only; let Pydantic raise internally

## Architecture patterns

- **Schema source of truth**: `WebServicePayload` in `models/qualtrics.py` → BQ schema via `shared/utils/bq_schemas.py` — change models first, schema follows
- **Config loading**: each function's `configs/` YAMLs merged alphabetically → validated against `AppConfig` in `shared/utils/config_models.py`
- **Idempotency**: fn2 checks `_processed` flag in BQ; fn3 checks `scheduled_followups` table before writing
- **Dependency groups**: deploy exports `main` + function-specific group to `requirements.txt`
- **`functions.yaml`**: single source of truth for all functions, SAs, IAM roles, secrets, triggers
- **`send_immediately` test flag**: carried on `IntakeProcessedMessage` / `FollowupSchedulingMessage` (`bool = False`). When `True`, fn3 schedules at now+16/32/48 min instead of fixed study times. Set via `manage_gateway.py test --now`; read from POST body by fn1 (not stored in BQ).

## Schema change workflow

`models/qualtrics.py` → `bq_schemas.py` → `web_service_payload.json` fixture → `test_models.py` → `manage_infra.py teardown` → `manage_infra.py setup`

Schema changes require BQ table teardown/recreate (streaming API limitation).

## Secrets / config

- `dkg-twilio-config` JSON blob in Secret Manager → `TWILIO_CONFIG` env var
- Local dev: env vars via `.envrc` / direnv; `manage_functions.py dev <fn>` prints required secrets
- Never hardcode secrets or project IDs in source files

## Worktree notes

- All tests are safe to run from any worktree (fully mocked, no network)
- **Never deploy from a worktree** — merge to `main` first, then deploy from main
- If running a local dev server (`dev` command), use a different port per worktree to avoid conflicts
