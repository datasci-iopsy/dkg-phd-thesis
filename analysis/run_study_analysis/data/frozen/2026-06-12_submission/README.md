# Data freeze: manuscript submission 2026-06-12

Frozen analytic inputs for the dissertation manuscript submitted 2026-06-12.
These files are byte-identical copies of `data/export/` at freeze time and are
the single source of truth for all numbers in the submitted manuscript.

- Verify integrity: `shasum -a 256 -c MANIFEST.sha256`
- BigQuery point-in-time snapshot: dataset `qualtrics_frozen_20260612`
  (zero-copy snapshot tables of all 8 physical tables in `qualtrics`;
  `survey_responses_classified` is a view, its SQL is archived here).
- The live pipeline remained running after the freeze; responses arriving
  after 2026-06-12 exist in the live `qualtrics` dataset only and are not
  part of the manuscript analytic sample.
- Do not re-run `make study_export` for this manuscript.
