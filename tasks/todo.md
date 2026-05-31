# Shift-Based Scheduling: Task List

See `tasks/plan.md` for acceptance criteria and verification steps per task.

---

## Slice A: Field plumbing (start here)

- [ ] **A1** `models/qualtrics.py` -- add `work_classification` + `work_shift` to `QID_MAP` (placeholder QIDs) and `WebServicePayload`
- [ ] **A2** `models/participant.py` -- add `work_shift: str | None` to `ParticipantData`
- [ ] **A3** `pubsub_utils.py` -- add `work_shift: str | None` to `IntakeProcessedMessage` and `FollowupSchedulingMessage`
- [ ] **A4** `run_qualtrics_scheduling/main.py` -- pass `payload.work_shift` into `IntakeProcessedMessage`
- [ ] **A5** `run_intake_confirmation/main.py` -- forward `message.work_shift` into `FollowupSchedulingMessage`
- [ ] **A6** Test fixtures + plumbing tests (`test_models.py`, `test_bq_schemas.py`, `test_intake_confirmation.py`)

**Checkpoint A**: `uv run pytest gcp/tests/ -v` passes. Field flows end-to-end with `None` as default.

---

## Slice B: Config-driven scheduling (after A)

- [ ] **B1** `config_models.py` -- add `ShiftTimesConfig` model; add `shift_times` field to `AppConfig`
- [ ] **B2** `run_followup_scheduling/configs/gcp_utils.yaml` -- add `shift_times` section with first-shift times + placeholders for other shifts
- [ ] **B3** `run_followup_scheduling/main.py` -- replace hardcoded `FOLLOWUP_TIMES` with `get_followup_times(message.work_shift)` config lookup
- [ ] **B4** `run_intake_confirmation/main.py` -- remove hardcoded `FOLLOWUP_TIMES`; update `format_sms_body` to generic shift language
- [ ] **B5** Tests (`test_followup_scheduling.py`, `test_intake_confirmation.py`) -- shift lookup, None fallback, SMS format

**Checkpoint B**: `uv run pytest gcp/tests/ -v` passes. `work_shift=None` path produces 9/13/17 times (unchanged).

---

## Slice C: Survey scripts (parallel with A/B)

- [ ] **C1** `.env` + `scripts/qualtrics/config.py` -- add `QUALTRICS_INTAKE_SURVEY_ID`
- [ ] **C2** `scripts/qualtrics/updater.py` -- add `add_question()` and `fetch_question_list()`
- [ ] **C3** `scripts/qualtrics/changes.py` -- add `QuestionAdd` dataclass + `INTAKE_ADDITIONS` list (work_classification + work_shift questions with display logic)
- [ ] **C4** `scripts/qualtrics/add_intake_questions.py` (new) -- runner with `--dry-run` flag
- [ ] **C5** Replace placeholder QIDs in `QID_MAP` and placeholder shift keys in `gcp_utils.yaml` after C4 runs against live API

**Checkpoint C**: Intake survey has two new unpublished questions. Real QIDs in `QID_MAP`. Config shift keys match survey choice labels exactly.

---

## Slice D: BQ + extraction (after A)

- [ ] **D1** Run `bq update --schema` to add `work_classification` and `work_shift` nullable columns to `stg_intake_responses`
- [ ] **D2** Create `survey_responses_classified` BQ VIEW with COALESCE defaults
- [ ] **D3** `deploy/backfill_intake_responses.py` -- add new fields to `COLUMN_MAP`
- [ ] **D4** Add `--all-responses` mode to extract all Qualtrics intake responses (including screened-out) into staging table

**Checkpoint D**: VIEW exists. Existing rows show `'first_shift'` default via VIEW. All historical responses in staging.

---

## Slice E: Full test suite

- [ ] **E1** `uv run pytest gcp/tests/ -v` -- zero failures
- [ ] **E2** Config round-trip: `first_shift` parses to `['09:00', '13:00', '17:00']`

**Checkpoint E**: All tests green.

---

## Deploy (user confirmation required for each step)

- [ ] D1: `bq update --schema` (no downtime)
- [ ] D2: create BQ VIEW
- [ ] Deploy fn1 (`run_qualtrics_scheduling`)
- [ ] Deploy fn2 (`run_intake_confirmation`)
- [ ] Deploy fn3 (`run_followup_scheduling`)
- [ ] User: publish updated intake survey in Qualtrics
- [ ] D4: extract all historical Qualtrics responses
- [ ] User: update `gcp/deploy/qualtrics_payloads/survey_0_payload.json`
- [ ] User: populate non-placeholder shift times in config YAML before fn3 deploy
