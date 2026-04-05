# CLAUDE.md

PhD dissertation: within-person fluctuation in burnout, need frustration, and turnover intentions.
Three pillars: `gcp/` (Python GCP pipeline), `analysis/run_power_analysis/` (R simulations), `analysis/run_synthetic_data/` (test data).
Python >=3.12,<3.13 (Poetry 2.2.1; requires `poetry-plugin-sort`, `poetry-plugin-export`) and R >= 4.4 (renv) managed separately. `.python-version` pins `3.12.11` for pyenv.
See `gcp/CLAUDE.md` and `analysis/CLAUDE.md` for domain specifics.

## Makefile

`make help` — primary user-facing interface for all commands (analysis, Python dev, GCP).
`make help_gcp` — GCP deployment detail. Raw commands below are still authoritative for Claude.

## Commands

```bash
# Onboarding (setup_r + setup_python + setup_hooks)
make setup

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
bash gcp/deploy/setup_gcp_vm.sh

# Deploy (from project root, never from a worktree)
python gcp/deploy/manage_functions.py dev <function-name>      # local dev server on :8080
python gcp/deploy/manage_functions.py deploy <function-name>   # deploy to GCP
python gcp/deploy/manage_infra.py setup|teardown               # BigQuery tables
python gcp/deploy/manage_gateway.py setup|test|teardown        # API Gateway
python gcp/deploy/manage_pubsub.py setup|teardown              # Pub/Sub topics
python gcp/deploy/manage_compute.py setup|status|ssh|scp|teardown  # Compute Engine VM
```

## Architecture overview

Three Cloud Run functions chained via Pub/Sub: `run_qualtrics_scheduling` (HTTP) → `run_intake_confirmation` (Pub/Sub) → `run_followup_scheduling` (Pub/Sub). API Gateway fronts function 1 with `x-api-key` validation and IAM JWT injection.

Power analysis: `main.sh` → `run_power_analysis.r` → parallel `simr` simulations (Arend & Schafer 2019). Dev: 3 combos × 10 sims. Prod: 3,645 cells × 1,000 sims on GCP `c3-highcpu-176`.

## Dependency freeze

Both lock files are frozen against accidental changes. Guardrails in place:
- `poetry.toml`: `installer.re-resolve = false` — `poetry install` uses the lock file exactly
- `.envrc`: `poetry check --lock` runs before every install; shell entry fails fast on drift
- `.Rprofile`: interactive `renv::snapshot()` and `renv::update()` require env var opt-in
- `scripts/hooks/pre-commit`: blocks commits staging `poetry.lock` or `renv.lock`

**Python update:** `poetry lock` → install → `ALLOW_LOCK_COMMIT=1 git commit` | **R update:** `make renv_snapshot` → `ALLOW_LOCK_COMMIT=1 git commit` | **Hook:** `make setup_hooks` (auto via `make setup`).

## Verification

After Python changes: `poetry check --lock` → `poetry run pytest gcp/tests/ -v` → `ruff check . && ruff format --check .` → `sqlfmt --check .`
After R changes: `bash analysis/tests/validate_r_structure.sh`
Schema changes: `models/qualtrics.py` → `bq_schemas.py` → `web_service_payload.json` → `test_models.py` → `manage_infra.py teardown/setup`

## Workflow

- Use Plan mode for complex or multi-file tasks; break large changes into reviewable chunks
- **Task branches**: for Claude-driven work, create a short-lived branch off the current branch (e.g., `main--claude-<topic>`), commit there, and let the user review the diff before merging
- Deploy commands (`manage_functions.py deploy`, `manage_infra.py`, `manage_gateway.py`, `manage_pubsub.py`, `manage_compute.py`) require explicit user confirmation — never run autonomously
- **Worktrees**: still valid when Claude needs to work in parallel while the user is actively editing; never run deploy commands from a worktree

## CodeRabbit review triage

When a prompt contains `coderabbit-instructions` in its source path, treat it as a CodeRabbit review to triage. The review profile is "assertive" — expect a mix of genuine issues and nitpicks.

**For each finding, assign a severity (1–5):**

| Severity | Meaning | Action |
|----------|---------|--------|
| 1 | Style nitpick, personal preference | Acknowledge, no change needed |
| 2 | Minor convention gap (e.g., missing docstring on a helper) | Note for future, skip unless trivial to fix |
| 3 | Valid suggestion that improves clarity or consistency | Fix if low-effort, otherwise flag for user |
| 4 | Real issue — logic bug, missing validation, security gap | **Fix and explain** |
| 5 | Critical — data loss, security vulnerability, broken pipeline | **Fix immediately, explain impact** |

**Process:**
1. List each finding with severity and a one-line rationale
2. Severity 4+: propose a concrete fix (diff or description)
3. Severity 1–2: acknowledge briefly, no changes unless user asks
4. Group findings by file when multiple
5. End with summary: total findings, count by severity, files touched

**Calibration** (assertive profile generates these frequently — do not over-react):
- "Add type hint" on internal helper → 2 (convention, not a bug)
- "Use `log_msg()` not `cat()`" → 3 (matches analysis/CLAUDE.md convention)
- "Missing `tryCatch()` in parallel worker" → 4 (silent failures in production)
- "Hardcoded secret / project ID" → 5 (security)
- "Consider renaming variable" → 1 (subjective preference)
