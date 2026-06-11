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

---

## Correlation Analysis

Two correlation matrices reported in the manuscript: between-person (L2 Pearson) and within-person (repeated-measures correlation; Bakdash & Marusich, 2017).

### Why rmcorr for within-person

The `correlation::correlation(multilevel = TRUE)` approach (lme4-based partial correlations) systematically attenuates within-person associations by partialling out all other predictors. `rmcorr` estimates the common intra-individual linear relationship while removing between-person variance via individual intercepts, without partialling. This is the appropriate estimator for an ESM design where within-person associations are the target of inference.

### Key between-person correlations (L2 Pearson, N = 322)

| Pair | r |
|---|---|
| PCB (br_mean) -- PCV (vio_mean) | .857 |
| PCB -- Job Satisfaction | -.625 |
| PCV -- Job Satisfaction | -.680 |
| Positive Affect -- Negative Affect | -.352 |
| Negative Affect -- PCV | .299 |

### Key within-person correlations (rmcorr, N = 322, 966 obs)

| Pair | r |
|---|---|
| PF -- CW | .651 |
| PF -- Turnover Intention | .315 |
| EE -- Turnover Intention | .301 |
| EE -- PF | .279 |
| NF Competence -- NF Relatedness | .492 |
| NF Competence -- NF Autonomy | .392 |
| NF Autonomy -- NF Relatedness | .300 |
| CW -- Turnover Intention | .220 |
| NF Competence -- Turnover Intention | .207 |

- **Manuscript figure**: `figs/corr/corr_between_within.svg`

---

## Measurement Model

### L2 Single-Level CFA (between-person scales)

Four factors measured once at intake: Positive Affect (POS_AFF, 5 items), Negative Affect (NEG_AFF, 5 items), PC Breach (PCB, 5 items), PC Violation (PCV, 4 items). Estimated with MLR.

**Fit**: χ²(146) = 250.83, *p* < .001; CFI = .967; TLI = .961; RMSEA = .052 [.041, .063]; SRMR = .046

All loadings significant (*p* < .001); standardized loadings range .508 -- .922.

**McDonald's omega**:

| Factor | ω |
|---|---|
| POS_AFF | .773 |
| NEG_AFF | .815 |
| PCB | .943 |
| PCV | .921 |

### L1 Multilevel CFA (within-person scales)

Seven factors measured at each timepoint: PF (5 items; pf3 excluded -- see Scale Scoring), CW (5 items), EE (3 items), NF Competence (4 items), NF Autonomy (4 items), NF Relatedness (4 items), ATCB marker (4 items). MCFA with within- and between-person decomposition (Lai, 2021); estimated with MLR.

**Fit**: χ²(712) = 1320.81, *p* < .001; CFI = .944; TLI = .936; RMSEA = .033 [.030, .036]; SRMR_within = .049; SRMR_between = .081

RMSEA is particularly strong (.033); SRMR_between (.081) slightly elevated relative to the within level, consistent with modest between-person item variance in daily diary designs.

**McDonald's omega -- within-level** (state reliability, key for ESM inference):

| Factor | ω_within |
|---|---|
| PF | .817 |
| CW | .852 |
| EE | .613 |
| NF Competence | .550 |
| NF Autonomy | .558 |
| NF Relatedness | .618 |
| ATCB (marker) | .492 |

**McDonald's omega -- between-level** (person-mean / trait reliability):

| Factor | ω_between |
|---|---|
| PF | .973 |
| CW | .985 |
| EE | .958 |
| NF Competence | .966 |
| NF Autonomy | .949 |
| NF Relatedness | .939 |
| ATCB (marker) | .983 |

**Notes for write-up**:
- Within-level omegas for NF facets (.550 -- .618) and EE (.613) are moderate. This is expected in ESM designs: state-level fluctuation carries more item-specific noise than stable trait scores. PF (.817) and CW (.852) show strong within-level reliability.
- Omega computed directly from λ, φ, θ parameter estimates (McDonald, 1999; Lai, 2021). semTools::compRelSEM() not used for MCFA levels due to deprecated config= argument in semTools >= 0.5-8.
- Negative between-level residual variances (Heywood cases) clamped to 0 before omega computation, consistent with semTools internal convention.
- Single-item measures excluded from CFA: Job Satisfaction (js1, tp1 only) and Turnover Intention (single item, L1).
- Cite: Bakdash & Marusich (2017) for rmcorr; Lai (2021) for MCFA omega; Vandenberg & Lance (2000) for measurement equivalence rationale (pf3 exclusion).

### CFA Marker Variable Technique

Abbreviated strategy from Williams et al. (2010) and Williams & McGonagle (2016), applied at **Level 1 (within-person) only**.

**Why Level 2 was not tested**: The L2 scales (POS_AFF, NEG_AFF, PCB, PCV) were collected at intake in a separate session from the ESM daily surveys. Common method variance from the momentary survey context (mood state, acquiescence, demand characteristics) can only co-contaminate measures administered within the same occasion. L2 and L1 constructs were not assessed concurrently; a marker variable test at L2 would address a source of variance that is structurally absent by design.

**Marker variable**: ATCB (Attitude Toward the Color Blue; Miller & Simmering, 2023; Miller et al., 2024), 4 items (atcb2, atcb5, atcb6, atcb7). ATCB was selected based on empirical validation of near-zero correlations with organizational behavior variables.

**Step 1 -- Marker evidence (ATCB within-person rmcorr)**:

| Pair | r |
|---|---|
| ATCB -- PF | -.040 |
| ATCB -- CW | -.022 |
| ATCB -- EE | -.034 |
| ATCB -- NF Competence | -.057 |
| ATCB -- NF Autonomy | -.023 |
| ATCB -- NF Relatedness | -.040 |
| ATCB -- Turnover Intention | -.017 |

All within-person associations between ATCB and substantive constructs are near zero (|r| < .10), confirming ATCB functions as a valid marker variable in this ESM sample.

**Step 2 -- Baseline**: The MCFA from the previous section (7-factor, CFI = .944, RMSEA = .033) serves as the Baseline (Model 1).

**Step 3 -- Method-U (free ATCB cross-loadings at L1)**: ATCB was allowed to freely cross-load on all 25 L1 substantive items. The Satorra-Bentler scaled chi-square difference test indicated no significant improvement in fit: SB-χ²(25) = 1.43, *p* = 1.00. The 25 additional cross-loading parameters contributed essentially zero improvement over the Baseline.

**Step 4 -- Method-R**: Not run; Method-U was not significant.

**Conclusion**: No evidence of common method bias at Level 1. Freely estimating ATCB cross-loadings on all within-person items produced no meaningful change in model fit, indicating that a common method factor does not account for systematic variance in the ESM responses. The marker variable technique supports the discriminant validity of the within-person measurement model.

- Cite: Williams et al. (2010); Williams & McGonagle (2016); Miller & Simmering (2023); Miller et al. (2024).
- Outputs: `figs/cfa/cfa_05_marker_evidence.csv`, `cfa_06_marker_fit.csv`, `cfa_07_marker_lrt.csv`

---

## Sections to Add

- [ ] Multilevel model specification (Slice 8)
- [ ] Hypothesis tests and effect sizes (Slice 8)
