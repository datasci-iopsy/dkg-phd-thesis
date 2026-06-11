# Methods Notes: Real-Data Analysis Pipeline

Running notes for the updated methods section. Sections added as each analysis phase completes.
Numbers are from the current pipeline run (N = 337 raw, data as of 2026-06-10).

---

## Recruitment and Sample

- Dual-source recruitment: CloudResearch Connect panel + snowball sampling.
- **CloudResearch classification**: `connect_id` matching `^[A-Za-z0-9]{32}$` (exactly 32 alphanumeric characters). Snowball participants who entered random text in the `connect_id` field are correctly classified as snowball based on pattern match, not null check.
- Raw intake responses: **337 participants**.

---

## ESM Protocol / Survey Design

- Three daily surveys per participant: 9AM (tp1), 1PM (tp2), 5PM (tp3).
- All three timepoints required for inclusion in the analytical sample.
- **Survey design omissions** (unintentional, unrecoverable):
  - `pf3` (SMBM Physical Fatigue item 3) absent from 1PM and 5PM surveys (`SV_eRKl4lgMZDAurT8`, `SV_6J3svun1r97AAHc`). Present at tp1 only.
  - `js1` (Job Satisfaction item) placed after survey end in 1PM and 5PM flows. Scored at tp1 only; NULL at tp2/tp3 by design.
- **Deduplication**: 14 participants submitted the same followup survey twice within hours. First submission retained (ordered by `_created_at ASC` within each `intake_response_id x survey_id` pair).

---

## Scale Scoring

### Physical Fatigue (PF) -- SMBM subscale

- Scored from **5 items**: pf1, pf2, pf4, pf5, pf6.
- `pf3` excluded from the composite at all timepoints to maintain measurement equivalence across tp1, tp2, and tp3. Using `pf3` at tp1 but not tp2/tp3 would conflate item composition with true within-person change. This is a deliberate measurement decision, not a missing data issue.
- Report omega for the 5-item version.
- Cite: measurement equivalence rationale (e.g., Vandenberg & Lance, 2000).

### Proration Rule (5-item scales: PF and CW)

- **When applied**: fewer than 5 but at least 4 items non-null (>= 80% item coverage).
- **Formula**: mean of available items (divide by count of non-null items, not by 5).
- **When NULL**: fewer than 4 items present (<80% coverage).
- **Scope**: 4 participants missing `pf4` at tp1 due to item-level non-response (< 0.2% of all person-observations). `cw_mean` subject to same rule by consistency; no known CW missingness in the current data.
- **Justification**: Raaijmakers (1999) and Fayers & Machin (2014) confirm proration introduces operationally negligible bias at >= 80% coverage on internally consistent scales. Item-level FIML was considered and rejected as disproportionate to the scope (4 observations out of 966).
- **Methods note**: "Four participants were missing responses on one item (pf4) at the 9AM timepoint due to item-level non-response. For these observations, the physical fatigue mean was computed from the four available items (80% item coverage). Given the high internal consistency of the scale and the minimal scope of the missing data (< 0.2% of observations), this approach is consistent with accepted thresholds (Raaijmakers, 1999)."

### Meeting Load Variables

- `meetings_count`: raw count capped at 8.
- `meetings_time`: minutes from survey response; supplemented by backfill from `meeting_time_supplement` table where primary field was missing; capped at 240 minutes. NULL where neither source provided a value.

---

## Careless Responding Screening

Six indices computed; three used for exclusion (Meade & Craig, 2012). Three retained as diagnostics only.

### Exclusion Criteria (flag >= 2 of 3 triggers exclusion)

| Criterion | Level | Threshold |
|---|---|---|
| Attention/instructed-response check | L1 (per timepoint) | Timepoint-specific expected response |
| Longstring index | L1 (per timepoint) + L2 (intake) | Sample-dependent cutoff |
| Mahalanobis distance | L1 (per timepoint) + L2 (intake) | Sample-dependent cutoff |

### Diagnostic Only (reported, not used for exclusion)

| Criterion | Rationale for exclusion from decision rule |
|---|---|
| IRV L1 (intra-individual response variability) | Supplementary; low overlap with exclusion flags |
| IRV L2 | Supplementary; no participants flagged in current sample |
| Survey duration | Weak discriminant in ESM designs: fast response at tp2/tp3 expected after practice; high false-positive risk |

### Results

- **337** participants screened.
- **15 excluded** (4.5%): all met >= 2 exclusion criteria.
- **322 retained** for analysis.
- **8 additional participants** flagged by >= 2 of all 6 indices (longstring + duration only); not excluded. Mahalanobis does not flag any of them, supporting their retention.
- Cite: Meade & Craig (2012); Curran (2016) for sequential multi-criterion framework.

---

## Analytical Sample

- **N = 322 participants**, **966 person-observations** (3 per participant).
- Level 1 (within-person): person-timepoint observations.
- Level 2 (between-person): person-level means and intake covariates.

---

## Sections to Add

- [ ] Correlation analysis (Slice 7)
- [ ] Measurement model / CFA (Slice 7)
- [ ] Multilevel model specification (Slice 8)
- [ ] Hypothesis tests and effect sizes (Slice 8)
