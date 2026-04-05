# Synthetic Data Analysis

Pipeline for validating the analysis plan against Claude-generated synthetic ESM data before collecting real participant responses. Mirrors the full analytical sequence that will be applied to study data.

## Overview

Four R scripts run in sequence, each writing figures and tables to `figs/`:

| Step | Script | Output directory | What it does |
|------|--------|-----------------|--------------|
| 1 | `eda.R` | `figs/eda/` | Descriptive stats, distributions, ICCs, missing data, spaghetti plots, lag-1 autocorrelations |
| 2 | `correlation.R` | `figs/eda/` | Bivariate correlations, repeated-measures correlations, L1/L2 correlation matrices |
| 3 | `measurement_model.R` | `figs/` | CFA factor structure, reliability (omega, alpha), common method variance diagnostics |
| 4 | `multilevel_model.R` | `figs/mlm/` | Model comparison (null → full), fixed/random effects, hypothesis tests, effect sizes |

## Input Requirements

Place CSV input files in `data/import/` before running. The analysis expects two files:
- Intake survey responses (L1 + L2 baseline variables)
- Follow-up survey responses (L1 time-varying variables, timepoints 2 and 3)

The Makefile guard `_check_synthetic_inputs` will error with a clear message if this directory is empty.

Current inputs (synthetic, Claude-generated):
- `data/import/claude_gen_syn_intake_responses_20260223.csv`
- `data/import/claude_gen_syn_followup_responses_20260223.csv`

## How to Run

**All four scripts in sequence (recommended):**

```bash
make synthetic_analysis
```

**Individual scripts:**

```bash
make synthetic_eda          # Step 1: EDA
make synthetic_correlation  # Step 2: Correlations
make synthetic_measurement  # Step 3: Measurement model
make synthetic_mlm          # Step 4: Multilevel models
```

**Prerequisites:** Complete Quick Start steps 1–4 in the root `README.md` (R + renv packages required).

## Output

All outputs write to `figs/`:
- `figs/eda/` — ~38 PDFs + select CSVs (descriptive statistics, ICC table, correlation comparison)
- `figs/mlm/` — model comparison, fixed/random effects, hypothesis tests, effect sizes, diagnostics

Figures are committed to the repository for reference.

## Data Pipeline (Optional — Data Already Exported)

The `data/export/` directory contains wide-format panel datasets merged from intake + follow-up CSVs via SQL scripts in `scripts/sql/`. These are pre-built and committed; you do not need to re-run the SQL pipeline unless changing the data schema.

If you do need to regenerate the panel export:

```bash
bash scripts/syn_intake_responses_infra.sh
bash scripts/syn_followup_responses_infra.sh
bash scripts/export_syn_fct_panel_responses_csv.sh
```
