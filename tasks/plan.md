# Shift-Based ESM Scheduling: Implementation Plan

Source: `docs/ideas/shift-based-scheduling.md`

Decisions locked in:
- BQ backfill: VIEW with COALESCE -- no teardown/recreate; `bq update --schema` adds nullable columns in place
- Scheduling times: config-driven YAML, read by fn3 at cold-start
- Staging table: ALL Qualtrics responses (eligible + screened-out) captured via API extraction
- User handles `gcp/deploy/qualtrics_payloads/survey_0_payload.json` update manually
- fn2 confirmation SMS: generic shift language (exact times TBD, not listed in confirmation)

---

## Dependency graph

```
Slice A (field plumbing) ─────────────────────────────────────────┐
  models → fn1 → Pub/Sub messages → fn3 receipt                   │
                                                                   ▼
Slice C (survey scripts) ──► real QIDs ──► update A's QID_MAP ──► Slice B (scheduling logic)
  updater extension + runner                                       config model + fn3 lookup
                                                                   fn2 SMS update
                                                                        │
                                                                        ▼
                                                               Slice D (BQ + extraction)
                                                               bq update, VIEW, backfill
                                                                        │
                                                                        ▼
                                                               Slice E (tests)
```

Slices A and C are independent and run in parallel.
Slice B depends on A (needs `work_shift` in the message model).
Slice D depends on A (BQ schema auto-generates from `WebServicePayload`).
Slice E depends on A through D.

---

## Slice A: Shift field end-to-end plumbing

Goal: `work_classification` and `work_shift` flow from intake payload through BQ write, `ParticipantData`, both Pub/Sub messages, and into fn3 receipt. No scheduling behavior change yet.

### A1 -- Add fields to `WebServicePayload` and `QID_MAP`

File: `gcp/cloud_run_functions/run_qualtrics_scheduling/models/qualtrics.py`

- Add to `QID_MAP` with placeholder QID strings (replaced after Slice C discovers real QIDs):
  ```python
  "work_classification": "QID_PLACEHOLDER_WC",
  "work_shift":          "QID_PLACEHOLDER_WS",
  ```
- Add to `WebServicePayload`:
  ```python
  work_classification: str | None = Field(
      default=None, description="DOL employment classification label"
  )
  work_shift: str | None = Field(
      default=None, description="Selected work shift label"
  )
  ```

Acceptance:
- `WebServicePayload.model_validate(payload_without_new_fields)` succeeds (nullable, backward compatible)
- `WebServicePayload.model_validate(payload_with_new_fields)` populates both fields
- `generate_schema(WebServicePayload)` includes both as NULLABLE STRING columns

Verification: `uv run pytest gcp/tests/test_models.py gcp/tests/test_bq_schemas.py -v`

### A2 -- Add `work_shift` to `ParticipantData`

File: `gcp/cloud_run_functions/run_qualtrics_scheduling/models/participant.py`

- Add: `work_shift: str | None = Field(default=None)`
- Update `followup_times` docstring to note it is superseded by config-driven lookup in fn3

Acceptance:
- Constructs with `work_shift=None` (existing participants)
- Constructs with `work_shift="first_shift"` (new participants)

### A3 -- Add `work_shift` to both Pub/Sub message models

File: `gcp/shared/utils/pubsub_utils.py`

- `IntakeProcessedMessage`: add `work_shift: str | None = Field(default=None, ...)`
- `FollowupSchedulingMessage`: add `work_shift: str | None = Field(default=None, ...)`

Acceptance:
- Both models validate with `work_shift` absent (backward compat for in-flight messages at deploy time)
- Both round-trip through `model_dump()` -> `model_validate()` with the field present

### A4 -- Pass `work_shift` through fn1

File: `gcp/cloud_run_functions/run_qualtrics_scheduling/main.py`

- When constructing `IntakeProcessedMessage`, add `work_shift=payload.work_shift`
- No change needed in `validation_utils.py` -- the field is read directly from `payload` in the handler

Acceptance:
- Payload with `WORK_SHIFT="first_shift"` produces `IntakeProcessedMessage(work_shift="first_shift")`
- Payload without `WORK_SHIFT` produces `IntakeProcessedMessage(work_shift=None)`

### A5 -- Forward `work_shift` through fn2

File: `gcp/cloud_run_functions/run_intake_confirmation/main.py`

- When constructing `FollowupSchedulingMessage`, add `work_shift=message.work_shift`

Acceptance: `FollowupSchedulingMessage` carries `work_shift` from the intake message unchanged.

### A6 -- Update test fixtures and field-plumbing tests

Files:
- `gcp/tests/fixtures/web_service_payload.json`: add `"WORK_CLASSIFICATION"` and `"WORK_SHIFT"` with placeholder label values
- `gcp/tests/test_models.py`: assert new fields on `WebServicePayload`
- `gcp/tests/test_bq_schemas.py`: assert `work_classification` and `work_shift` in `SURVEY_RESPONSES_COLUMNS`
- `gcp/tests/test_intake_confirmation.py`: assert `work_shift` is forwarded from `IntakeProcessedMessage` to `FollowupSchedulingMessage`

**Checkpoint A**: All tests pass. `work_shift` flows through every layer. Existing payloads (without new fields) still validate.

---

## Slice B: Config-driven scheduling

Depends on: Slice A complete

Goal: fn3 reads shift times from config and routes `FOLLOWUP_TIMES` by `work_shift`. `None` falls back to first-shift (existing participant behavior unchanged). fn2 drops hardcoded times.

### B1 -- Add `ShiftTimesConfig` to config models

File: `gcp/shared/utils/config_models.py`

Add:
```python
class ShiftTimesConfig(BaseModel):
    """Shift label -> three HH:MM delivery times. Used by fn3."""
    default_shift: str = Field(..., description="Key used when work_shift is None")
    shifts: dict[str, list[str]] = Field(
        ..., description="shift_label -> [HH:MM, HH:MM, HH:MM]"
    )
```

Add to `AppConfig`: `shift_times: ShiftTimesConfig | None = None`

### B2 -- Add `shift_times` to fn3 config YAML

File: `gcp/cloud_run_functions/run_followup_scheduling/configs/gcp_utils.yaml`

```yaml
shift_times:
  default_shift: "first_shift"
  shifts:
    first_shift:      ["09:00", "13:00", "17:00"]
    second_shift:     ["PLACEHOLDER", "PLACEHOLDER", "PLACEHOLDER"]
    third_shift:      ["PLACEHOLDER", "PLACEHOLDER", "PLACEHOLDER"]
    part_time_am:     ["PLACEHOLDER", "PLACEHOLDER", "PLACEHOLDER"]
    part_time_mid:    ["PLACEHOLDER", "PLACEHOLDER", "PLACEHOLDER"]
    part_time_pm:     ["PLACEHOLDER", "PLACEHOLDER", "PLACEHOLDER"]
    part_time_variable: ["PLACEHOLDER", "PLACEHOLDER", "PLACEHOLDER"]
```

Shift key strings must match exactly what Qualtrics sends as `work_shift` label values. Finalize after C3 defines the survey question choice labels.

### B3 -- Replace hardcoded `FOLLOWUP_TIMES` in fn3

File: `gcp/cloud_run_functions/run_followup_scheduling/main.py`

- Remove module-level `FOLLOWUP_TIMES: list[time] = [time(9,0), time(13,0), time(17,0)]`
- Add helper (at module level, after config load):
  ```python
  def get_followup_times(work_shift: str | None) -> list[time]:
      shift_key = work_shift or config.shift_times.default_shift
      raw = config.shift_times.shifts[shift_key]
      return [time.fromisoformat(t) for t in raw]
  ```
- In `followup_scheduling_handler`: replace `FOLLOWUP_TIMES` with `get_followup_times(message.work_shift)`

Acceptance:
- `message.work_shift = None` -> first-shift times (9/13/17); existing participant behavior unchanged
- `message.work_shift = "second_shift"` -> configured second-shift times
- Unknown key logs error and raises `KeyError` (no SMS scheduled for bad shift data; Pub/Sub retries)

### B4 -- Update fn2 confirmation SMS

File: `gcp/cloud_run_functions/run_intake_confirmation/main.py`

- Remove module-level `FOLLOWUP_TIMES` constant
- Update `format_sms_body` signature and body:
  ```python
  def format_sms_body(selected_date: date, timezone: str, work_shift: str | None) -> str:
      date_str = selected_date.strftime("%B %d, %Y")
      shift_label = work_shift.replace("_", " ").title() if work_shift else "your work day"
      return (
          f"Thank you for participating in our study! "
          f"We received your selected follow-up date: {date_str}. "
          f"You will receive three surveys during {shift_label} ({timezone})."
      )
  ```
- Update call site: `body = format_sms_body(selected_date, message.timezone, message.work_shift)`

Acceptance:
- `work_shift=None` -> "during your work day"
- `work_shift="first_shift"` -> "during First Shift"

### B5 -- Add fn3 shift scheduling tests

File: `gcp/tests/test_followup_scheduling.py`

Add:
- `work_shift=None` -> default shift times (9/13/17)
- `work_shift="second_shift"` -> configured second-shift times
- Unknown `work_shift` key -> `KeyError` (or logged error + 0 messages; verify actual behavior)
- `ShiftTimesConfig` validates correctly from YAML

File: `gcp/tests/test_intake_confirmation.py`

Add:
- `format_sms_body(date, tz, None)` -> does not raise, contains "your work day"
- `format_sms_body(date, tz, "first_shift")` -> contains "First Shift"

**Checkpoint B**: Scheduling logic is shift-aware. Existing participant path is verified identical to today.

---

## Slice C: Survey scripts (parallel with A and B)

Goal: extend `scripts/qualtrics/` to POST two new questions to the intake survey via the Qualtrics Definitions API. Do not publish. Discover real QIDs for A1.

### C1 -- Add intake survey ID to config

- `.env`: add `QUALTRICS_INTAKE_SURVEY_ID=SV_86vMYNR8SdVDfEi`
- `scripts/qualtrics/config.py`: add `qualtrics_intake_survey_id: str` to `ScriptConfig` and validator

Acceptance: `ScriptConfig()` loads and validates the new field from `.env`.

### C2 -- Extend `updater.py` with question-add capability

File: `scripts/qualtrics/updater.py`

Add:
- `add_question(survey_id, question_body, base_url, api_key) -> str` -- POST to `/survey-definitions/{survey_id}/questions`; returns the new `QuestionID`
- `fetch_question_list(survey_id, base_url, api_key) -> list[dict]` -- GET `/survey-definitions/{survey_id}/questions` to inspect existing structure

Display logic is set per-question via the question body's `DisplayLogic` key in the PUT/POST body. No separate endpoint needed for basic branching.

Acceptance:
- `add_question` with a minimal MC question body returns a QID string
- A dry-run mode (print body, skip POST) is available via a parameter flag

### C3 -- Define intake question structures

File: `scripts/qualtrics/changes.py`

Add `QuestionAdd` dataclass alongside existing `QuestionChange`:
```python
@dataclass(frozen=True)
class QuestionAdd:
    survey_id: str
    question_body: dict
    description: str
```

Add `INTAKE_ADDITIONS: list[QuestionAdd]` with two entries:

1. `work_classification` -- multiple-choice question with DOL labels:
   - Employee - Full-Time
   - Employee - Part-Time
   - Independent Contractor
   - Temporary or Contract Worker
   - Other

2. `work_shift` -- multiple-choice question with `DisplayLogic` branching on `work_classification` answer:
   - Full-time / Other -> First/Day Shift, Second/Evening Shift, Third/Night Shift
   - Part-time / Contractor / Temp -> AM Part-Time, Mid Part-Time, PM Part-Time, Variable/Flexible

Use `inspect_surveys.py` to GET an existing intake question body first; copy its `QuestionType`, `Selector`, `SubSelector` structure exactly.

### C4 -- Create `add_intake_questions.py` runner

File: `scripts/qualtrics/add_intake_questions.py` (new)

Structure mirrors `update_surveys.py`:
1. Load `ScriptConfig`
2. For each `QuestionAdd` in `INTAKE_ADDITIONS`: call `add_question()`, log returned QID
3. Print QID mapping so A1 placeholders can be replaced
4. `--dry-run` flag: print bodies without POSTing

Acceptance:
- `--dry-run` prints question bodies without calling the API
- Live run logs real QIDs for `work_classification` and `work_shift`

### C5 -- Replace placeholder QIDs (after C4 runs)

After C4 returns real QIDs:
- `models/qualtrics.py` `QID_MAP`: replace `QID_PLACEHOLDER_WC` and `QID_PLACEHOLDER_WS`
- `gcp_utils.yaml` `shift_times.shifts` keys: replace `PLACEHOLDER` times with real HH:MM values; confirm shift key strings match Qualtrics choice labels exactly

**Checkpoint C**: Two new questions exist in the intake survey (unpublished). Real QIDs in `QID_MAP`. Config YAML shift keys match survey choice labels.

---

## Slice D: BQ schema update, VIEW, and expanded extraction

Depends on: Slice A complete (schema auto-generates from updated `WebServicePayload`)

### D1 -- Add nullable columns to `stg_intake_responses` in place

BQ supports adding nullable columns to streaming tables without teardown.

Command:
```bash
bq update \
  --schema "work_classification:STRING,work_shift:STRING" \
  dkg-phd-thesis:qualtrics.stg_intake_responses
```

Or regenerate the full schema from the model and pass it:
```bash
uv run python -c "
import json, sys
sys.path.insert(0, 'gcp/cloud_run_functions/run_qualtrics_scheduling')
sys.path.insert(0, 'gcp/shared')
from models.qualtrics import WebServicePayload
from utils.bq_schemas import generate_schema, SYSTEM_FIELDS
schema = generate_schema(WebServicePayload, system_fields=SYSTEM_FIELDS)
print(json.dumps([{'name': f.name, 'type': f.field_type, 'mode': f.mode} for f in schema]))
" | bq update --schema /dev/stdin dkg-phd-thesis:qualtrics.stg_intake_responses
```

Acceptance:
- `bq show dkg-phd-thesis:qualtrics.stg_intake_responses` shows `work_classification` and `work_shift` as NULLABLE STRING
- Existing rows unchanged (NULL for new columns)
- Streaming writes continue uninterrupted during the update

### D2 -- Create BQ VIEW for analysis

```sql
CREATE OR REPLACE VIEW `dkg-phd-thesis.qualtrics.survey_responses_classified` AS
SELECT
  * EXCEPT(work_classification, work_shift),
  COALESCE(work_classification, 'employee_full_time') AS work_classification,
  COALESCE(work_shift, 'first_shift')                 AS work_shift
FROM `dkg-phd-thesis.qualtrics.stg_intake_responses`
```

Run via `bq query --use_legacy_sql=false`.

Acceptance:
- Existing participant row: `work_shift` returns `'first_shift'` from the view
- Screened-out participant row: same defaults
- New participant row with actual shift: returns the actual shift value

### D3 -- Update `backfill_intake_responses.py` for new columns

File: `gcp/deploy/backfill_intake_responses.py`

Add to `COLUMN_MAP`:
```python
"WORK_CLASSIFICATION": "WORK_CLASSIFICATION",
"WORK_SHIFT":          "WORK_SHIFT",
```

Note: CSV column headers from Qualtrics depend on question labels. Verify against an export after the survey is published before running.

### D4 -- Extract all Qualtrics responses including screened-out

Extend `backfill_intake_responses.py` with `--all-responses` mode that:
1. Calls the Qualtrics Responses API to export ALL completed intake survey responses
2. Compares against BQ to find any not yet in `stg_intake_responses`
3. Builds and POSTs each missing response to the live intake endpoint

Screened-out responses will have `phone=NULL`, `selected_date=NULL`. fn1 writes them to BQ with `_processed=FALSE`, then `extract_participant_data` returns `None` (missing phone/date), so no Pub/Sub message fires. No SMS risk.

Acceptance:
- After run, `SELECT COUNT(*) FROM stg_intake_responses` > 55
- Screened-out rows: `_processed=FALSE`, `phone=NULL`, `selected_date=NULL`
- Existing eligible rows: `_processed=TRUE` unchanged

**Checkpoint D**: BQ table has new nullable columns. VIEW exists with correct COALESCE defaults. All historical responses captured.

---

## Slice E: Test suite completion

Depends on: Slices A through D

### E1 -- Full test run confirms zero regressions

```bash
uv run pytest gcp/tests/ -v
```

All existing tests pass with updated fixtures. New tests from A6, B5 pass.

### E2 -- Confirm config round-trip

```bash
uv run python -c "
from pathlib import Path
import sys; sys.path.insert(0, 'gcp/shared')
from utils.config_loader import load_config
config = load_config(Path('gcp/cloud_run_functions/run_followup_scheduling/configs'))
print(config.shift_times.default_shift)
print(config.shift_times.shifts['first_shift'])
"
```

Expected output:
```
first_shift
['09:00', '13:00', '17:00']
```

**Checkpoint E**: Full test suite passes. Config parses correctly.

---

## Deploy sequence (user confirms each step)

After all slices pass locally and code is merged to main:

1. `bq update --schema` (D1) -- adds nullable columns; no downtime
2. `bq query` to create VIEW (D2)
3. Deploy fn1 (`run_qualtrics_scheduling`) -- new fields start flowing into BQ
4. Deploy fn2 (`run_intake_confirmation`) -- generic SMS; forwards work_shift
5. Deploy fn3 (`run_followup_scheduling`) -- config-driven scheduling
6. User publishes updated intake survey in Qualtrics
7. Run D4 (extract all historical responses including screened-out)
8. User updates `gcp/deploy/qualtrics_payloads/survey_0_payload.json`

Deploy commands (require explicit confirmation):
```bash
uv run gcp/deploy/manage_functions.py deploy run_qualtrics_scheduling
uv run gcp/deploy/manage_functions.py deploy run_intake_confirmation
uv run gcp/deploy/manage_functions.py deploy run_followup_scheduling
```

---

## Out of scope

- Dashboard branch (`claude/dsio-66-dashboard-expansion`): rebases onto main after this work merges
- Analysis code
- Exact shift times for non-first shifts: user populates config YAML before Step 5 deploy
- `survey_0_payload.json` update: user action
- Publishing the survey: user action
