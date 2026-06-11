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

## Multilevel Model

### Model building sequence (M0 to M7b)

Cross-classified data: N = 322 L2 units (participants) x 3 L1 observations per person (966 total). DV: turnover_intention_mean (single-item, 1-5 scale). Centering: person-mean centering (CWC) for L1 predictors via datawizard::demean(); grand-mean centering for L2 predictors. Following Curran & Bauer (2011) and Enders & Tofighi (2007). ML for LRTs; REML for final parameter tables.

**Model fit summary** (ML estimation):

| Model | AIC | BIC | R2_mar | R2_con | tau_00 | LRT chi2 | df | p |
|---|---|---|---|---|---|---|---|---|
| M0: Unconditional means | 2226.8 | 2241.4 | .000 | .800 | .989 | -- | -- | -- |
| M1: Fixed time | 2224.7 | 2244.2 | .002 | .803 | .990 | 10.12 | 1 | .001 |
| M2: Random slope | 2207.2 | 2236.5 | .002 | .831 | .872 | 21.43 | 2 | <.001 |
| M3: L1 within-person (H1a, H2a) | 2166.6 | 2239.7 | .046 | .841 | .890 | 107.40 | 9 | <.001 |
| M4: L1 within + between (H1b, H2b) | 1969.3 | 2081.4 | .495 | .841 | .376 | 251.27 | 8 | <.001 |
| M5: L2 study vars (H4a, H4b, H5) | 1924.6 | 2061.1 | .576 | .841 | .290 | 76.67 | 5 | <.001 |
| M6: Demographic covariates | 1968.5 | 2153.7 | .575 | .843 | .294 | 6.27 | 10 | .792 |

- **ICC (M0)**: R2_conditional = .800, confirming substantial between-person variance in TI (prerequisite met).
- **M4 drives the explained variance**: R2_marginal jumps from .046 to .495 when between-person means enter; L1 person-mean components carry the bulk of the predictive signal.
- **M6 non-significant**: LRT p = .792; demographic covariates (gender, is_remote, edu_lvl, ethnicity) add no incremental fit over M5. recruitment_source was entered in M3-M5 per the manuscript's mandatory control specification and was not re-screened.

### Hypothesis tests

**Supported hypotheses (p < .05, correct direction)**:

| Hypothesis | Term | Estimate | p | Model |
|---|---|---|---|---|
| H1a:comp | WP competence frustration | +.138 | .003 | M3 |
| H2a:pf | WP physical fatigue | +.180 | <.001 | M3 |
| H2a:ee | WP emotional exhaustion | +.218 | <.001 | M3 |
| H2b:pf | BP physical fatigue mean | +.520 | <.001 | M4 |
| H2b:ee | BP emotional exhaustion mean | +.544 | <.001 | M4 |
| H4a | BP PC breach | +.131 | .049 | M5 |
| H5 | BP job satisfaction | -.178 | <.001 | M5 |

**Not supported**:

| Hypothesis | Term | Estimate | p | Note |
|---|---|---|---|---|
| H1a:auto | WP autonomy frustration | -.008 | .806 | Wrong direction |
| H1a:relt | WP relatedness frustration | +.006 | .900 | ns |
| H1b (all) | BP NF facet means | .042 to .107 | .262 to .454 | ns |
| H2a:cw | WP cognitive weariness | +.008 | .834 | ns |
| H2b:cw | BP cognitive weariness mean | -.227 | .002 | Wrong direction |
| H3a:count | Count x NF composite | -.075 | .308 | ns |
| H3a:time | Time x NF composite | -.002 | .399 | ns |
| H3b:count | Count x burnout composite | +.007 | .920 | ns |
| H3b:time | Time x burnout composite | +.003 | .179 | ns |
| H4b | BP PC violation | +.092 | .217 | ns |

### Slope heterogeneity (rho_beta; Aguinis & Culpepper, 2015)

| Predictor | rho_beta | tau11 | Magnitude |
|---|---|---|---|
| PF (within) | .053 | .311 | medium |
| EE (within) | .020 | .189 | small-medium |
| Comp NF (within) | .036 | .305 | small-medium |
| Burnout composite (within) | .031 | .333 | small-medium |
| CW (within) | .012 | .066 | small-medium |
| NF composite (within) | .012 | .145 | small-medium |
| Auto NF (within) | .006 | .030 | negligible |
| Relt NF (within) | .003 | .033 | negligible |

rho_beta quantifies the proportion of within-person variance explained by slope heterogeneity (i.e., individual differences in how strongly each L1 predictor relates to TI). PF has the largest rho_beta (.053), indicating moderate person-level variability in the PF-TI slope. Most other predictors show small-medium or negligible slope heterogeneity.

- Outputs: `figs/mlm/mlm_04_hypothesis_tests.md`, `mlm_08_iccbeta.csv`, model diagnostics at `mlm_diag_model_*.svg`
- Cite: Curran & Bauer (2011); Enders & Tofighi (2007); Aguinis & Culpepper (2015).

## Post Hoc Power Confirmation

### Analytic strategy

Post hoc power estimates are drawn from the pre-study simulation grid (Arend & Schafer, 2019) run prior to data collection (`analysis/run_power_analysis/`). The GCP production run covered N_Level2 ∈ {100, ..., 1500}, ICC ∈ {0.10, 0.30, 0.50}, and standardized fixed effects ∈ {0.10, 0.30, 0.50} for L1 direct, L2 direct, and cross-level interaction effects (1,000 simulations per cell; Kenward-Roger tests).

Three features of the actual design require explicit handling:

1. **N = 322 falls between grid nodes.** Nodes at N = 300 and N = 400 bracket the actual sample; power values below are interpolated or stated as bounds.
2. **TI ICC ≈ 0.80 exceeds the grid maximum (0.50).** Grid ICC = 0.50 is used as the nearest reference. For L1 (within-person) effects, higher ICC means less within-person variance available to detect state-level fluctuation, so ICC = 0.50 estimates are **optimistic upper bounds** for L1 power. For L2 (between-person) effects, higher ICC concentrates between-person signal and does not meaningfully degrade L2 power; ICC = 0.50 is **conservative** for L2.
3. **Observed standardized effects computed post hoc:** L1 effects standardized using WP SD; L2 effects using BP (person-mean) SD.

### Observed standardized effect sizes

Standardized beta = beta_unstd * (SD_pred / SD_TI), computed from actual WP and BP SDs in the analytical sample (N = 322).

**L1 (within-person, WP-centered):**

| Hypothesis | Predictor | beta_unstd | SD_WP_pred | SD_WP_TI | std_beta |
|---|---|---|---|---|---|
| H1a:comp | WP Competence Frus. | +.138 | .379 | .406 | ~.13 |
| H2a:pf | WP Physical Fatigue | +.180 | .460 | .406 | ~.20 |
| H2a:ee | WP Emotional Exhaustion | +.218 | .366 | .406 | ~.20 |

**L2 (between-person, person-mean):**

| Hypothesis | Predictor | beta_unstd | SD_BP_pred | SD_BP_TI | std_beta |
|---|---|---|---|---|---|
| H2b:pf | BP Physical Fatigue | +.520 | .909 | 1.034 | ~.46 |
| H2b:ee | BP Emotional Exhaustion | +.544 | .592 | 1.034 | ~.31 |
| H4a | BP PC Breach | +.131 | 1.045 | 1.034 | ~.13 |
| H5 | BP Job Satisfaction | -.178 | 1.151 | 1.034 | ~.20 |

### Power estimates from simulation grid (ICC = 0.50; N = 300 and N = 400)

**L1 direct effects:**

| std_beta | N = 300 | N = 400 | Approx. N ≈ 322 |
|---|---|---|---|
| .10 (small) | .63-.65 | .71-.77 | ~.65 |
| .20 (interpolated) | ~.87* | ~.93* | ~.89* |
| .30+ (medium) | 1.00 | 1.00 | 1.00 |

*Linear interpolation between the .10 and .30 grid nodes.

These are upper bounds for L1: actual power at ICC = 0.80 is lower than shown.

**L2 direct effects:**

| std_beta | N = 300 | N = 400 | Approx. N ≈ 322 |
|---|---|---|---|
| .10 (small) | .31-.35 | .40-.46 | ~.36 |
| .20 (interpolated) | ~.65* | ~.72* | ~.67* |
| .30+ (medium) | .99-1.00 | 1.00 | >=.99 |

*Linear interpolation between the .10 and .30 grid nodes.

These are conservative estimates for L2: actual power at ICC = 0.80 is equal to or greater than shown.

### Verdict by supported hypothesis

| Hypothesis | std_beta | Approx. power | p | Assessment |
|---|---|---|---|---|
| H1a:comp | ~.13 | <=.65 (upper bound) | .003 | Low power; finding significant; caution given small effect near detection floor |
| H2a:pf | ~.20 | <=.89 (upper bound) | <.001 | Moderate-to-adequate power; supported |
| H2a:ee | ~.20 | <=.89 (upper bound) | <.001 | Moderate-to-adequate power; supported |
| H2b:pf | ~.46 | >=.99 | <.001 | Well-powered; supported |
| H2b:ee | ~.31 | >=.99 | <.001 | Well-powered; supported |
| H4a | ~.13 | ~.36-.67 | .049 | Low power; borderline p; replicate before treating as established |
| H5 | ~.20 | ~.67 (conservative) | <.001 | Moderate power; strong p consistent with true effect |

### Null findings

**Non-significant L1 effects** (H1a:auto beta=-.008; H1a:relt beta=+.006; H2a:cw beta=+.008): standardized effects all below .01. These are not underpowered null results -- they are essentially zero effects. Power to detect std_beta < .05 would be negligible at any N in the grid.

**Non-significant L2 effects** (H1b NF facet means: std_beta ≈ .04--.09; H4b PCV: p = .217): effects are below the small-effect threshold. At std_beta = .10, L2 power ≈ .36 (N = 322, ICC = 0.50). The simulation cannot distinguish between a true zero and an underpowered small effect at this N for these predictors. Replication at larger N would be needed to confirm absence of NF facet effects on TI.

**Cross-level interactions** (H3a, H3b): all non-significant. The simulation shows cross-level interaction power is consistently below .50 for small effects (std = .10) at N = 300-400 with ICC = 0.50. These null findings are inconclusive; the design was not adequately powered to detect small interaction effects at this N.

### Scope limitation

The simulation grid does not include ICC = 0.80. All L1 power estimates are upper bounds; the true power for L1 effects at ICC = 0.80 is lower. The L2 estimates are conservative. Supplementary simulations at ICC = 0.80 (N = 300-400, n_lvl1 = 3) would tighten these bounds and are noted as a future addition if requested during peer review.

- Cite: Arend & Schafer (2019); Kenward-Roger tests via `simr`.
- Source data: `analysis/run_power_analysis/data/power_analysis_results_20260316_183228.csv` (GCP prod run, 3,645 cells x 1,000 sims).

---

## Sections to Add

- [ ] Publication-ready tables (Slice 9)
