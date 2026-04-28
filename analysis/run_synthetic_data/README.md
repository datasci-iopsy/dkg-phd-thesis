# Synthetic Data Analysis

Pipeline for validating the analysis plan against Claude-generated synthetic ESM data before collecting real participant responses. Mirrors the full analytical sequence that will be applied to study data.

## Overview

Six R scripts run in sequence. Step 1 screens for careless responding and writes the cleaned dataset used by Steps 2–5. Step 6 reads CSV outputs from Steps 2–5 to produce publication-ready Word tables.

| Step | Script | Output | What it does |
|------|--------|--------|--------------|
| 1 | `data_quality.R` | `figs/data_quality/`, `data/export/…cleaned….csv` | Careless responding detection (longstring, IRV, Mahalanobis, duration); excludes flagged participants |
| 2 | `eda.R` | `figs/eda/` | Descriptive stats, distributions, ICCs, missing data, spaghetti plots, lag-1 autocorrelations |
| 3 | `correlation.R` | `figs/corr/` | Bivariate correlations, repeated-measures correlations, L1/L2 correlation matrices |
| 4 | `measurement_model.R` | `figs/cfa/` | CFA factor structure, reliability (omega, alpha), common method variance diagnostics |
| 5 | `multilevel_model.R` | `figs/mlm/` | Model comparison (null → full), fixed/random effects, hypothesis tests, effect sizes |
| 6 | `publication_tables.R` | `tables/` | APA-formatted Word tables (demographics, descriptives/correlations, CFA, MLM, hypotheses) |

Step 6 is a downstream pass: run `make synthetic_analysis` first, then `make synthetic_tables`.

## Input Requirements

Place CSV input files in `data/import/` before running. The analysis expects two files:
- Intake survey responses (L2 baseline variables)
- Follow-up survey responses (L1 time-varying variables, timepoints 1–3)

The Makefile guard `_check_synthetic_inputs` will error with a clear message if this directory is empty.

Current inputs (synthetic, Claude-generated):
- `data/import/claude_gen_syn_intake_responses_20260223.csv`
- `data/import/claude_gen_syn_followup_responses_20260223.csv`

## How to Run

**All six steps in sequence (recommended):**

```bash
make synthetic_analysis
```

**Individual steps:**

```bash
make synthetic_data_quality    # Step 1: Careless responding screening
make synthetic_eda             # Step 2: EDA
make synthetic_correlation     # Step 3: Correlations
make synthetic_measurement     # Step 4: Measurement model
make synthetic_mlm             # Step 5: Multilevel models
```

**Publication tables (run after `synthetic_analysis`):**

```bash
make synthetic_tables          # Step 6: Word .docx tables
```

Steps 2–5 load the cleaned dataset written by Step 1. If the cleaned file is absent, the script stops with an error. Run Step 1 first.

**Prerequisites:** Complete Quick Start steps 1–4 in the root `README.md` (R packages managed by uvr required).

## Data Quality Screening

`data_quality.R` (Step 1) implements careless responding detection using the `careless` package (Yentes & Wilhelm, 2018) adapted for a **repeated-measures design**. Each of the three within-day surveys is evaluated independently; a participant is excluded based on their pattern of flagging across all surveys.

### Why per-survey analysis matters

In a cross-sectional design, careless responding can be detected once per person. In a 3-survey ESM design, a participant may respond carefully in the morning and afternoon but rush through the evening survey, or vice versa. Collapsing across surveys (e.g., taking the person mean) would obscure this pattern. This script computes all L1 indices separately for each survey and flags at the survey level before aggregating to the person level for the exclusion decision.

### Screening criteria

Six criteria are evaluated. A person-level criterion flag is `TRUE` if it was triggered on **any** survey.

| # | Criterion | Applied to | Default threshold | Rationale |
|---|-----------|-----------|-------------------|-----------|
| 1 | **Longstring L1** | Each survey (30 items) | > 10 consecutive identical responses | Straight-lining within a survey; 10/30 = 33% |
| 2 | **Longstring L2** | Intake block (20 items, once) | > 10 consecutive identical responses | Straight-lining in the baseline intake survey |
| 3 | **IRV L1** | Each survey (30 items) | SD < 0.50 | Very flat response distribution within a survey |
| 4 | **IRV L2** | Intake block (20 items, once) | SD < 0.25 | Very flat distribution in intake items |
| 5 | **Duration** | Each survey completion time | < 90 seconds | Rushing; 90 s / 30 items ≈ 3 s per item |
| 6 | **Mahalanobis** | L1 scale means per survey + L2 scale means once | p < .001 (chi-sq cutoff) | Multivariate outlier in the scale-mean space |

For the Mahalanobis criterion, two distances are computed and combined into a single flag:
- **L1 Mahalanobis** (chi-sq df = 8): computed independently on the 8 L1 scale means at each survey. Detects survey-specific multivariate outliers.
- **L2 Mahalanobis** (chi-sq df = 5): computed once on the 5 intake scale means. Detects overall baseline outliers.

A participant is flagged on criterion 6 if either distance exceeds its cutoff on any survey.

### Exclusion rule

A participant is **excluded** when flagged on **2 or more** of the 6 criteria (Curran, 2016, multi-flag approach). This reduces false positives relative to any-flag exclusion while still catching systematic careless responding.

All thresholds and the minimum flag count are defined at the top of `data_quality.R` and can be adjusted there without changing downstream logic.

### Diagnostic outputs

All figures overwrite on each run (no date stamps); CSVs in `figs/data_quality/` are gitignored and regenerated locally.

| File | Type | Content |
|------|------|---------|
| `dq_01_longstring_l1_by_survey.svg` | Figure | 3-panel faceted histogram of L1 longstring per survey with flag threshold line and per-survey flag count |
| `dq_02_irv_l1_by_survey.svg` | Figure | 3-panel faceted histogram of L1 IRV per survey |
| `dq_03_duration_by_survey.svg` | Figure | 3-panel faceted histogram of completion time per survey |
| `dq_04_mahalanobis_l1_by_survey.svg` | Figure | 3-panel rank plot of L1 Mahalanobis distances per survey; flagged points colored red |
| `dq_05_l2_indices.svg` | Figure | 3-panel composite for intake (L2) longstring, IRV, and Mahalanobis |
| `dq_06_flag_summary.svg` | Figure | Grouped bar chart of flags by criterion and survey; person-level flag count distribution with exclusion coloring |
| `dq_07_screening_detail.csv` | Table | One row per person × survey; columns: `longstring_l1`, `irv_l1`, `duration`, `mahad_l1_dist`, and per-criterion flags |
| `dq_08_person_summary.csv` | Table | One row per person; per-survey raw values (tp1/tp2/tp3 columns), worst-case aggregates, L2 indices, all criterion flags, `n_flags`, `exclude` |
| `dq_09_excluded_participants.csv` | Table | Excluded participant IDs with flag details |

### References

Curran, P. G. (2016). Methods for the detection of carelessly invalid responses in self-report inventories. *Journal of Experimental Social Psychology*, 66, 125–137.

Yentes, R. D., & Wilhelm, F. (2018). The careless R package: Bad data before bad analyses. *Practical Assessment, Research & Evaluation*, 23(2).

## Output

- `figs/data_quality/` — careless responding diagnostic SVGs (6 figures); CSVs regenerated locally on each run
- `data/export/syn_qualtrics_fct_panel_responses_cleaned.csv` — panel dataset after careless responding exclusions
- `figs/eda/` — SVG figures and select CSVs/MD tables (descriptive statistics, ICC table, correlation comparison, ~38 outputs)
- `figs/corr/` — SVG correlation matrices and CSV data (L1 Pearson, L2 Pearson, MLM-based, rmcorr within-person)
- `figs/cfa/` — CSV + MD tables for fit indices, factor loadings, and omega reliability (no figures; all outputs are tabular)
- `figs/mlm/` — model comparison, fixed/random effects, hypothesis tests, effect sizes, diagnostics (SVG + CSV/MD)
- `tables/` — publication-ready Word tables for the dissertation manuscript:
  - `table_01_demographics.docx` — participant characteristics
  - `table_02_descriptives_correlations.docx` — means, SDs, reliabilities, correlations
  - `table_03_cfa_results.docx` — CFA fit indices and standardized loadings
  - `table_04a_mlm_results.docx` — M0–M6 fixed effects and variance components
  - `table_04b_moderation.docx` — M7a/M7b meeting × burnout/NF moderation
  - `table_05_hypothesis_tests.docx` — hypothesis test summary

`figs/` outputs are committed to the repository for reference. `tables/` outputs are gitignored (regenerated from committed CSVs).

## Data Pipeline (Optional — Data Already Exported)

The `data/export/` directory contains the wide-format panel dataset (`syn_qualtrics_fct_panel_responses.csv`) merged from intake and follow-up CSVs via the BigQuery SQL pipeline. This is pre-built and committed; you do not need to re-run the pipeline unless changing the data or schema.

### Scripts

**`scripts/generate_synthetic_data.py`** — generates psychologically calibrated synthetic intake and follow-up CSVs and uploads them to BigQuery (`syn_qualtrics` dataset). Replaced the earlier `syn_intake_responses_infra.sh` and `syn_followup_responses_infra.sh` scripts.

**`scripts/sql/`** — three BigQuery SQL scripts run in order:
1. `int_intake_responses_scored.sql` — transforms raw intake responses into a scored intermediate table
2. `int_followup_responses_scored.sql` — transforms raw follow-up responses into a scored intermediate table
3. `fct_panel_responses.sql` — joins the two intermediate tables into the wide-format fact table, applying eligibility filters

**`scripts/export_syn_fct_panel_responses_csv.sh`** — queries `fct_panel_responses` from BigQuery and writes `syn_qualtrics_fct_panel_responses.csv` to `data/export/`. Requires `gcloud` auth and the `dkg-phd-thesis` project.

### Full regeneration sequence

```bash
python scripts/generate_synthetic_data.py           # generate + upload raw CSVs to BQ
# run SQL scripts in order via bq query or the BQ console
bash scripts/export_syn_fct_panel_responses_csv.sh  # export fact table to data/export/
```
