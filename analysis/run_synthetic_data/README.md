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

Steps 2–5 load the cleaned dataset written by Step 1. If the cleaned file is absent (e.g., running a step individually before Step 1 has run), the script falls back to the raw export and logs a warning.

**Prerequisites:** Complete Quick Start steps 1–4 in the root `README.md` (R + renv packages required).

## Output

- `figs/data_quality/` — careless responding diagnostic SVGs and CSV screening summary (longstring, IRV, Mahalanobis, duration distributions; per-participant flag table)
- `data/export/syn_qualtrics_fct_panel_responses_cleaned_YYYYMMDD.csv` — panel dataset after careless responding exclusions
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

The `data/export/` directory contains the wide-format panel dataset (`syn_qualtrics_fct_panel_responses_YYYYMMDD.csv`) merged from intake and follow-up CSVs via the BigQuery SQL pipeline. This is pre-built and committed; you do not need to re-run the pipeline unless changing the data or schema.

### Scripts

**`scripts/generate_synthetic_data.py`** — generates psychologically calibrated synthetic intake and follow-up CSVs and uploads them to BigQuery (`syn_qualtrics` dataset). Replaced the earlier `syn_intake_responses_infra.sh` and `syn_followup_responses_infra.sh` scripts.

**`scripts/sql/`** — three BigQuery SQL scripts run in order:
1. `int_intake_responses_scored.sql` — transforms raw intake responses into a scored intermediate table
2. `int_followup_responses_scored.sql` — transforms raw follow-up responses into a scored intermediate table
3. `fct_panel_responses.sql` — joins the two intermediate tables into the wide-format fact table, applying eligibility filters

**`scripts/export_syn_fct_panel_responses_csv.sh`** — queries `fct_panel_responses` from BigQuery and writes a dated CSV to `data/export/`. Requires `gcloud` auth and the `dkg-phd-thesis` project.

### Full regeneration sequence

```bash
python scripts/generate_synthetic_data.py           # generate + upload raw CSVs to BQ
# run SQL scripts in order via bq query or the BQ console
bash scripts/export_syn_fct_panel_responses_csv.sh  # export fact table to data/export/
```
