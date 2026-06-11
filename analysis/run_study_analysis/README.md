# run_study_analysis

Official ESM analysis pipeline for the dissertation study using real participant data from
BigQuery (`dkg-phd-thesis.qualtrics`). Mirrors the structure of `../run_synthetic_data/` with
two additional data-layer outputs and a cleaner prep-module architecture.

## Data outputs

**(a) Participation summary** (`fct_participation_summary.sql`)

Participant-grain table (1 row per person) showing the intake-to-followup completion funnel:
per-timepoint completed flags, `n_followups` (0 to 3), `n_total` (of 4), `completion_rate`,
intake and followup timestamps/dates, eligibility booleans, per-timepoint attention-check
status, and `recruitment_source`.

Exported to `data/export/qualtrics_participation_summary.csv` for reporting. This table uses
a LEFT JOIN to include everyone who entered the funnel, regardless of completion.

**(b) Analytical fact table** (`fct_panel_responses.sql`)

Participant-timepoint grain table used by all R analyses. Applies 5 eligibility gates and
listwise attention-check deletion before export. Exported to
`data/export/qualtrics_fct_panel_responses.csv`.

## Careless responding screening

`scripts/R/data_quality.R` **excludes** participants flagged on >= 2 of the following
3 indicators (Meade & Craig 2012):

1. Instructed-response / attention checks (failed at any timepoint)
2. LongString index (L1 per-survey and L2 intake block)
3. Mahalanobis distance (L1 per-survey and L2 intake block)

Two additional indicators are **computed and reported diagnostically** but are NOT used
for exclusion:

4. IRV (intra-individual response variability) -- L1 and L2
5. Survey duration -- L1 per-survey

## Prep modules

Scripts source `utils/prep_levels.R` and `utils/prep_mlm.R` instead of repeating
data-wrangling logic inline.

- `prep_levels.R`: `partition_levels(df)` splits the panel into L1 (within-person) and
  L2 (between-person) frames.
- `prep_mlm.R`: `prepare_mlm_frame(df, defs)` applies within-person centering (CWC),
  grand-mean centering of L2 predictors, demographic coding, and burnout/NF composite
  construction. Returns a model-ready frame.

## Recruitment source

`recruitment_source` is derived from `connect_id` in the intake SQL:

- **CloudResearch**: `connect_id` matches `^[A-Za-z0-9]{32}$` (32 alphanumeric chars)
- **Snowball**: anything else (including snowball participants who mis-entered the field)

## `meeting_time_supplement`

`meetings_time` is a backfilled variable from `qualtrics.meeting_time_supplement` (joined on
`response_id` + `survey_id` in `int_followup_responses_scored.sql`). It is NULL where no
supplement record exists. Do not use `connect_id` as a join key for this table (238 NULLs).

## Pipeline sequence

```
# SQL data layer (requires explicit user confirmation before bq runs)
bq query int_intake_responses_scored.sql
bq query int_followup_responses_scored.sql
bq query fct_participation_summary.sql
bq query fct_panel_responses.sql

# CSV exports
bash scripts/export_study_participation_summary_csv.sh
bash scripts/export_study_fct_panel_responses_csv.sh

# R analysis sequence (run from project root)
make study_data_quality    # Step 1: careless responding screening -> cleaned CSV
make study_analysis        # Steps 1-5: data_quality + eda + correlation + measurement + mlm
make study_tables          # Step 6: publication-ready Word .docx tables
```

## Variable definitions

See `utils/data_loader.R` (`VARIABLE_DEFS`) for the canonical variable group lists.
