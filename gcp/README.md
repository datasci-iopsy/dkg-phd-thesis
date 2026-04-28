# gcp/

Survey response ETL pipeline for a longitudinal ESM study. Receives Qualtrics Web Service task payloads through a GCP API Gateway, validates them with Pydantic across three Cloud Run functions chained via Pub/Sub, sends participant SMS confirmations and scheduled follow-up surveys via Twilio, and writes all records to BigQuery.

- [gcp/](#gcp)
  - [How it works](#how-it-works)
  - [CLI tools](#cli-tools)
    - [manage\_functions.py: Cloud Run function lifecycle](#manage_functionspy-cloud-run-function-lifecycle)
    - [manage\_gateway.py: API Gateway lifecycle](#manage_gatewaypy-api-gateway-lifecycle)
    - [manage\_pubsub.py: Pub/Sub topic lifecycle](#manage_pubsubpy-pubsub-topic-lifecycle)
    - [manage\_infra.py: BigQuery provisioning](#manage_infrapy-bigquery-provisioning)
    - [manage\_compute.py: Compute Engine VM lifecycle](#manage_computepy-compute-engine-vm-lifecycle)
  - [Configuration](#configuration)
  - [Secrets](#secrets)
  - [Updating the schema](#updating-the-schema)
  - [Testing locally with cURL](#testing-locally-with-curl)
  - [Running tests](#running-tests)
  - [Dependencies](#dependencies)
  - [Adding a new function](#adding-a-new-function)

Four Cloud Run functions live under `cloud_run_functions/`, each with its own `main.py` and `configs/`. Shared utilities (`bq_schemas.py`, `config_loader.py`, `pubsub_utils.py`, etc.) live in `shared/utils/`. Deployment scripts and YAML configs live in `deploy/`. Tests under `tests/` are fully mocked — no GCP credentials or network access needed.

## How it works

The pipeline processes completed survey responses in real time through three Cloud Run functions connected by two Pub/Sub topics.

A participant completes the intake survey in Qualtrics, which triggers a Workflow Web Service task. The task POSTs the full response as a JSON body with semantic field names (e.g., `"PA1": "Always"`, `"timezone": "US/Central"`) to the API Gateway endpoint. The university's GCP organization policy prohibits unauthenticated Cloud Run invocations, so the API Gateway sits in front: it validates a static API key sent in an `x-api-key` header, then forwards the request to Cloud Run with a proper IAM JWT injected. See [`gateway.yaml`](deploy/gateway.yaml) for the routing configuration.

**Function 1: `run_qualtrics_scheduling`** ([main.py](cloud_run_functions/run_qualtrics_scheduling/main.py)) — HTTP trigger. Validates the incoming JSON against `WebServicePayload`, a Pydantic model with 34 typed fields: 2 required system identifiers (`response_id`, `survey_id`) and 32 optional fields covering consent, eligibility, scheduling, demographics, and 20 psychometric scale items. Fields are optional because Qualtrics survey logic may route participants to the end early if they fail screening. On successful validation, all fields are written as explicit BigQuery columns to the `stg_intake_responses` table via the streaming API. The BigQuery schema is generated directly from the `WebServicePayload` model at import time ([`bq_schemas.py`](shared/utils/bq_schemas.py)), so there is a single source of truth for field names and types. Participant scheduling data (phone, date, timezone) is extracted and validated, then published as an `IntakeProcessedMessage` to `dkg-intake-processed`. If the publish fails, the function still returns 200 to Qualtrics since the BigQuery write already succeeded and `_processed` remains `FALSE` for visibility.

**Function 2: `run_intake_confirmation`** ([main.py](cloud_run_functions/run_intake_confirmation/main.py)) — Pub/Sub trigger on `dkg-intake-processed`. Decodes the CloudEvent message, checks BigQuery for idempotency (`_processed` flag), sends an SMS via Twilio confirming the participant's follow-up schedule, publishes a `FollowupSchedulingMessage` to `dkg-followup-scheduling`, and updates `_processed = TRUE`. If SMS fails, the function raises so Pub/Sub retries with exponential backoff. Malformed messages are acknowledged to prevent infinite retries.

**Function 3: `run_followup_scheduling`** ([main.py](cloud_run_functions/run_followup_scheduling/main.py)) — Pub/Sub trigger on `dkg-followup-scheduling`. Checks the `scheduled_followups` BigQuery table for idempotency (keyed by `response_id`). Builds three survey URLs with participant-specific query parameters (Connect ID, response ID, survey number). Schedules three SMS messages via the Twilio Message Scheduling API — one for each daily time slot (9:00 AM, 1:00 PM, 5:00 PM in the participant's local timezone). Writes scheduling records (Twilio message SIDs) to BigQuery only after all three Twilio calls succeed. A `send_immediately` test flag (set via `manage_gateway.py test --now`) bypasses fixed times and schedules at now+16/32/48 min for rapid end-to-end testing.

**Function 4: `run_followup_response`** ([main.py](cloud_run_functions/run_followup_response/main.py)) — HTTP trigger, fronted by the API Gateway at the `/followup` path. This is the terminal inbound endpoint for completed ESM survey responses. All three daily surveys (9AM/1PM/5PM) POST to this endpoint; the `timepoint` field in the payload distinguishes them. Validates the incoming JSON against `FollowupWebServicePayload` (a Pydantic model in `models/followup.py`) and writes to the `followup_raw` BigQuery table via `FOLLOWUP_RESPONSES_SCHEMA`. No Twilio, no Pub/Sub publishing. Validation failures return 400; successful writes return 200 with `response_id` and `timepoint`.

## CLI tools

Five scripts live in `gcp/deploy/` and are run from the project root. All use argparse, validate their configuration with Pydantic, and support `--help`.

### manage_functions.py: Cloud Run function lifecycle

```bash
# Local development (starts functions-framework on port 8080)
python gcp/deploy/manage_functions.py dev run-qualtrics-scheduling

# Local development on a custom port
python gcp/deploy/manage_functions.py dev run-qualtrics-scheduling --port 9090

# Deploy to GCP
python gcp/deploy/manage_functions.py deploy run-qualtrics-scheduling

# Tear down (interactive confirmation)
python gcp/deploy/manage_functions.py teardown run-qualtrics-scheduling

# Tear down (skip confirmation)
python gcp/deploy/manage_functions.py teardown run-qualtrics-scheduling --force

# List all configured functions
python gcp/deploy/manage_functions.py list
```

The `dev` command copies `shared/` into the function directory, starts a local server, and cleans up on exit. It also prints any secrets the function expects so you can set them as environment variables (via `.envrc` / direnv).

The `deploy` command exports a `requirements.txt` via `uv export` (using the function's dependency group), copies `shared/`, deploys via `gcloud functions deploy`, and cleans up local artifacts. If the function declares a `service_account` in [`functions.yaml`](deploy/functions.yaml), deploy creates the service account (if it does not exist), grants the declared IAM roles, and passes it to gcloud via `--service-account`.

The `teardown` command deletes the Cloud Run function, removes leftover Artifact Registry container images, clears the generated `requirements.txt`, and deletes the function's dedicated service account.

All function configuration lives in [`functions.yaml`](deploy/functions.yaml). Each entry defines `source_dir`, `dependency_group`, `entry_point`, `trigger`, `allow_unauthenticated`, and optionally `secrets` and `service_account` (with `name`, `display_name`, and `roles`). The `trigger` field supports `http` (generates `--trigger-http`) and `topic` (generates `--trigger-topic=TOPIC_ID`, requires `trigger_topic` field).

### manage_gateway.py: API Gateway lifecycle

```bash
# Provision gateway, service account, and API key
python gcp/deploy/manage_gateway.py setup

# Show current state of all gateway resources
python gcp/deploy/manage_gateway.py status

# Send the test fixture payload through the live gateway
python gcp/deploy/manage_gateway.py test

# Tear down all gateway resources (interactive confirmation)
python gcp/deploy/manage_gateway.py teardown

# Tear down (skip confirmation)
python gcp/deploy/manage_gateway.py teardown --force
```

The `setup` command enables required GCP APIs (`apigateway`, `servicemanagement`, `servicecontrol`, `apikeys`), creates a dedicated service account (`dkg-api-gateway`) with the Cloud Run Invoker role, resolves the target Cloud Run function URL from [`functions.yaml`](deploy/functions.yaml), generates an OpenAPI 2.0 spec, deploys the API config and gateway, and creates a GCP API key restricted to the gateway's managed service. The resulting gateway URL and API key are what you configure in the Qualtrics Workflow Web Service task.

The `test` command sends the fixture payload ([`web_service_payload.json`](tests/fixtures/web_service_payload.json)) through the live gateway end-to-end, verifying the full chain from API key validation through Cloud Run invocation to BigQuery insert.

The `teardown` command removes the gateway, API config, API resource, GCP API key, and the gateway service account.

All gateway configuration lives in [`gateway.yaml`](deploy/gateway.yaml), which specifies the API ID, gateway ID, location, service account details, and which Cloud Run function to route to.

### manage_pubsub.py: Pub/Sub topic lifecycle

```bash
# Create the Pub/Sub topic
python gcp/deploy/manage_pubsub.py setup

# Show topic state and any attached subscriptions
python gcp/deploy/manage_pubsub.py status

# Delete the topic (interactive confirmation)
python gcp/deploy/manage_pubsub.py teardown

# Delete the topic (skip confirmation)
python gcp/deploy/manage_pubsub.py teardown --force
```

`manage_pubsub.py` manages the two Pub/Sub topics that chain the three functions: `dkg-intake-processed` (fn1 → fn2) and `dkg-followup-scheduling` (fn2 → fn3). The script only manages topics themselves. Eventarc push subscriptions are created automatically when each consuming function is deployed with a `topic` trigger via `manage_functions.py`.

All topic configuration lives in [`pubsub.yaml`](deploy/pubsub.yaml). Project and region are read from [`functions.yaml`](deploy/functions.yaml) to avoid duplication.

### manage_infra.py: BigQuery provisioning

```bash
# Check current state of dataset and tables
python gcp/deploy/manage_infra.py status

# Create dataset and all tables with defined schemas (idempotent)
python gcp/deploy/manage_infra.py setup

# Delete tables (preserves dataset, interactive confirmation)
python gcp/deploy/manage_infra.py teardown

# Delete tables (skip confirmation)
python gcp/deploy/manage_infra.py teardown --force
```

`manage_infra.py` reads dataset and table names from [`gcp_config.yaml`](cloud_run_functions/run_qualtrics_scheduling/configs/gcp_config.yaml) (the same file the function uses at runtime), so there is no drift between what the script provisions and what the function writes to. Only tables with schemas registered in `TABLE_REGISTRY` (inside the script) are created by `setup`; unregistered tables appear in `status` as "no schema defined yet" and are skipped.

The config defines five tables: `intake_raw` and `intake_clean` for the enrollment survey, `followup_raw` and `followup_clean` for the three repeated-measures surveys, and `scheduled_followups` for Twilio scheduling records. Currently `intake_raw` and `scheduled_followups` have registered schemas; the others are provisioned as their schemas are finalized.

### manage_compute.py: Compute Engine VM lifecycle

```bash
# Create VM and print bootstrap instructions
python gcp/deploy/manage_compute.py setup

# Show VM state and external IP
python gcp/deploy/manage_compute.py status

# SSH into the VM
python gcp/deploy/manage_compute.py ssh

# Download results from the VM
python gcp/deploy/manage_compute.py scp

# Delete VM (interactive confirmation)
python gcp/deploy/manage_compute.py teardown

# Delete VM (skip confirmation)
python gcp/deploy/manage_compute.py teardown --force
```

`manage_compute.py` manages a single high-CPU VM for running R power analysis simulations (see [`analysis/run_power_analysis/`](../analysis/run_power_analysis/)). The VM runs Ubuntu 22.04 LTS and is bootstrapped with [`setup_gcp_vm.sh`](deploy/setup_gcp_vm.sh), which installs R >= 4.4, system libraries, and installs R packages via `uvr sync`. No GCP service account or API credentials are needed — the VM only runs R.

Machine type, zone, and disk size are configured in [`compute.yaml`](deploy/compute.yaml). The default `c3-highcpu-176` provides 176 vCPUs (174 workers after reserving 2 for OS overhead).

## Configuration

Runtime configuration for each function lives in YAML files under its `configs/` directory. The config loader ([`config_loader.py`](shared/utils/config_loader.py)) merges all YAML files in the directory alphabetically and validates the result against the `AppConfig` Pydantic model ([`config_models.py`](shared/utils/config_models.py)). Missing or invalid fields produce clear validation errors at startup. Optional config sections (`qualtrics`, `pubsub`, `secret_manager`) can be omitted by functions that do not need them.

**[`run_qualtrics_scheduling/configs/gcp_config.yaml`](cloud_run_functions/run_qualtrics_scheduling/configs/gcp_config.yaml)**: GCP project ID, compute region, BigQuery multi-region location, dataset name, all four table names, and the Pub/Sub topic ID for publishing intake-processed messages.

**[`run_qualtrics_scheduling/configs/qualtrics_config.yaml`](cloud_run_functions/run_qualtrics_scheduling/configs/qualtrics_config.yaml)**: Qualtrics REST API base URL and survey URL base (used for constructing follow-up survey links).

**[`run_intake_confirmation/configs/gcp_utils.yaml`](cloud_run_functions/run_intake_confirmation/configs/gcp_utils.yaml)**: GCP project ID, compute region, BigQuery references, and the Pub/Sub topic ID for publishing follow-up scheduling messages.

**[`run_followup_scheduling/configs/gcp_utils.yaml`](cloud_run_functions/run_followup_scheduling/configs/gcp_utils.yaml)**: GCP project ID, compute region, BigQuery references (including `scheduled_followups` table), and follow-up survey configuration (Qualtrics survey base URL and three survey IDs corresponding to the 9 AM, 1 PM, and 5 PM time slots).

Secrets (`QUALTRICS_API_KEY`, `QUALTRICS_WEBHOOK_SECRET`) are currently commented out of the scheduling function's deployment configuration. The API Gateway handles inbound authentication, and the Web Service task sends complete payloads, eliminating the need for outbound Qualtrics API calls in the active pipeline. The `SecretManagerConfig` model and `qualtrics_utils.fetch_single_response()` function are retained for manual lookups if needed. To re-enable secrets, uncomment the `secrets` block in [`functions.yaml`](deploy/functions.yaml) and add the `secret_manager` key back to `gcp_config.yaml`.

For local development, any needed environment variables can be set via `.envrc` / direnv or exported manually.

## Secrets

The intake confirmation and followup scheduling functions both use Twilio for SMS. Credentials are stored as a single JSON secret in Secret Manager and injected as the `TWILIO_CONFIG` environment variable at deploy time.

**One-time setup** (create the secret and set its value):

First, create a JSON file with your Twilio credentials. The `.keys/` directory is already in `.gitignore`.

```bash
mkdir -p .keys
```

```json
// .keys/twilio-config.json
{
  "account_sid": "ACxxxxxxxx",
  "auth_token": "xxxxxxxx",
  "from_number": "+1xxxxxxxxxx",
  "messaging_service_sid": "MGxxxxxxxx"
}
```

Then create the secret and populate it from the file:

```bash
# Create the secret resource (user-managed replication required
# by the university's org policy on resource locations)
gcloud secrets create dkg-twilio-config \
  --project=dkg-phd-thesis \
  --replication-policy=user-managed \
  --locations=us-east4

# Set the secret value from the JSON file
gcloud secrets versions add dkg-twilio-config \
  --project=dkg-phd-thesis \
  --data-file=.keys/twilio-config.json
```

Replace the placeholder values with your actual Twilio credentials. The `from_number` must be an E.164-formatted Twilio phone number you own. The `messaging_service_sid` is required by the followup scheduling function for Twilio's Message Scheduling API.

**Verify the secret** (confirm it was stored correctly):

```bash
gcloud secrets versions access latest \
  --secret=dkg-twilio-config \
  --project=dkg-phd-thesis
```

**Update the secret** (e.g., after rotating your auth token):

Edit `.keys/twilio-config.json` with the new values, then:

```bash
gcloud secrets versions add dkg-twilio-config \
  --project=dkg-phd-thesis \
  --data-file=.keys/twilio-config.json
```

Adding a new version does not require redeploying the function. The `:latest` version alias in [`functions.yaml`](deploy/functions.yaml) resolves to the newest version on each cold start.

## Updating the schema

When a survey question changes or a new field is added, four files need updating. The BigQuery schema regenerates automatically from the Pydantic model, so there is no separate schema definition to maintain.

1. **[`models/qualtrics.py`](cloud_run_functions/run_qualtrics_scheduling/models/qualtrics.py)**: Update `QID_MAP` if question IDs changed. Add, remove, or modify fields on `WebServicePayload`. Each field needs a type annotation and a `Field(...)` with a description.

2. **[`manage_infra.py`](deploy/manage_infra.py)**: If adding an entirely new table, register it in `TABLE_REGISTRY` with its schema, partition field, cluster fields, and description. For changes to existing tables, the schema is picked up automatically from [`bq_schemas.py`](shared/utils/bq_schemas.py). *Note*: Partitioning small tables is generally not recommended. There are tests in place to check for it in case this project scales, but at the current time, clustering will suffice.

3. **[`web_service_payload.json`](tests/fixtures/web_service_payload.json)**: Update the fixture to match the new payload shape. Every field on `WebServicePayload` must be present with a valid value.

4. **[`test_models.py`](tests/test_models.py)**: Update or add assertions for new/changed fields. If scale items changed, update the label sets in `test_positive_affect_labels`, `test_negative_affect_labels`, or `test_breach_violation_labels`.

After making changes, run the test suite to confirm everything is consistent:

```bash
uv run pytest gcp/tests/ -v
```

Key things the tests catch after a schema change: QID_MAP names that do not match `WebServicePayload` fields, insert row keys that do not match the generated schema, non-serializable values, duplicate column names, and missing partition/cluster fields.

**BigQuery caveat:** The streaming API does not support in-place schema changes on existing tables. If you modify the schema, you need to tear down and recreate the table:

```bash
python gcp/deploy/manage_infra.py teardown --force
python gcp/deploy/manage_infra.py setup
```

## Testing locally with cURL

Start the local dev server and send the fixture payload:

```bash
# Terminal 1: start the server
python gcp/deploy/manage_functions.py dev run-qualtrics-scheduling

# Terminal 2: send a test payload
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d @gcp/tests/fixtures/web_service_payload.json
```

A successful response returns `{"status": "success", ...}` with a 200. Validation failures return a 400 with a descriptive error message. Note that local dev mode bypasses the API Gateway, so no API key is needed; the gateway authentication chain can be tested end-to-end with `manage_gateway.py test`.

## Running tests

```bash
# All tests
uv run pytest gcp/tests/ -v
```

```bash
# All tests with coverage
uv run pytest gcp/tests/ -v \
  --cov=gcp/cloud_run_functions/run_qualtrics_scheduling \
  --cov=gcp/shared/utils \
  --cov-report=term-missing
```

```bash
# Individual test files
uv run pytest gcp/tests/test_models.py -v
uv run pytest gcp/tests/test_bq_schemas.py -v
uv run pytest gcp/tests/test_config.py -v
uv run pytest gcp/tests/test_validation.py -v
uv run pytest gcp/tests/test_intake_confirmation.py -v
uv run pytest gcp/tests/test_followup_scheduling.py -v
uv run pytest gcp/tests/test_followup_response.py -v
```

Tests mock BigQuery calls and use Flask test request contexts, so no GCP credentials or network access are needed.

## Dependencies

Dependencies are managed by uv with `[dependency-groups]` in `pyproject.toml`:

- base (`[project.dependencies]`): Shared dependencies used by all functions (pydantic, PyYAML).
- `fn-qualtrics-scheduling`: Intake webhook (Flask, functions-framework, google-cloud-bigquery, google-cloud-pubsub).
- `fn-intake-confirmation`: SMS confirmation (functions-framework, google-cloud-bigquery, twilio, cloudevents).
- `fn-followup-scheduling`: Follow-up SMS scheduling (functions-framework, google-cloud-bigquery, twilio, cloudevents).
- `fn-followup-response`: Followup response ingestion (functions-framework, google-cloud-bigquery). No Twilio or Pub/Sub.
- `dev`: Development tools (pytest, pytest-cov, ruff, radian).

At deploy time, `manage_functions.py` runs `uv export --no-dev --group <group>` to produce a `requirements.txt` that Cloud Run uses to build the container. New functions get their own dependency group in `pyproject.toml` and an entry in [`functions.yaml`](deploy/functions.yaml).

## Adding a new function

1. Create a new directory under `cloud_run_functions/` with `main.py`, `configs/`, and any `models/` or `utils/` modules.
2. Add a `[dependency-groups]` entry in `pyproject.toml` for the function's unique dependencies.
3. Add an entry in [`functions.yaml`](deploy/functions.yaml) with `source_dir`, `dependency_group`, `entry_point`, `trigger`, and a `service_account` block with the roles the function needs.
4. Add the function directory to `sys.path` in [`conftest.py`](tests/conftest.py) so test imports resolve.
5. Write tests under `gcp/tests/`.
