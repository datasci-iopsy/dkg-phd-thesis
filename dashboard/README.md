# dashboard/

**Live:** <https://esm-study-dashboard.netlify.app/>

Interactive, client-side results dashboard for the dissertation. It presents a static snapshot of the study analysis (frozen 2026-06-12, the submission snapshot) as a tabbed single-page app: no server-side code, no build step, just HTML/CSS/JS reading a pre-built JSON file.

- [What it shows](#what-it-shows)
- [How the data is built](#how-the-data-is-built)
- [Running it locally](#running-it-locally)
- [Deployment](#deployment)
- [Data snapshot](#data-snapshot)

## What it shows

`index.html` renders 10 tabs, each backed by data in `data/dashboard.json` and drawn with Chart.js 4 (loaded from CDN) plus plain HTML/CSS for tables and cards:

1. **The Study**, conceptual research model and design overview
2. **The Sample**, participant counts, recruitment funnel, demographics
3. **Correlations**, within-person and between-person correlation matrices
4. **Variance Story**, ICC and variance decomposition by construct
5. **Measurement**, CFA fit, reliability, marker-variable and invariance checks
6. **Model Explorer**, fit statistics and fixed effects across the M0-M7b model sequence
7. **Effect Sizes**, standardized and level-specific effect sizes, forest plot
8. **Hypotheses**, a scorecard of the 17 directional hypotheses
9. **Discussion**, takeaways and future directions
10. **Limitations**, study limitations in plain language

## How the data is built

`data/dashboard.json` is generated from the frozen study-analysis outputs, never hand-written:

```bash
uv run dashboard/scripts/build_dashboard_data.py
```

The script reads CSVs under `../analysis/run_study_analysis/figs/{eda,corr,mlm,cfa}/`, writes the single output file `data/dashboard.json`, and validates a set of anchor values (participant count, observation count, ICC, hypothesis tally, model counts) before exiting, failing loudly if the frozen CSVs and the hardcoded anchors disagree. It has no dependencies beyond the Python standard library.

The full mapping from each JSON key to its source CSV is documented in [`data/MANIFEST.md`](data/MANIFEST.md); that file is the source of truth for provenance, not this README.

## Running it locally

The page fetches `data/dashboard.json` at runtime, so opening `index.html` directly via `file://` will not work (the fetch is blocked by browser same-origin rules). Serve it over HTTP from this directory instead:

```bash
cd dashboard
netlify dev
# or, without the Netlify CLI:
python -m http.server
```

## Deployment

Deployed to Netlify as a static site. `netlify.toml` sets `publish = "."` with no build command, the committed `data/dashboard.json` is what ships; there is no CI build step. `.netlify/` is local Netlify CLI scratch state and is not part of the deployed app.

## Data snapshot

This dashboard reflects the 2026-06-12 submission snapshot: N = 336 participants, n = 1,008 observations, ICC(TI) approximately 0.79, 7 of 17 hypotheses supported. To regenerate against a newer analysis run, rerun the study pipeline (`make study_all` from the project root, see [`../analysis/run_study_analysis/README.md`](../analysis/run_study_analysis/README.md)) and then rerun the build script above.
