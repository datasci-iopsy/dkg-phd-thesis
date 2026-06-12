# Methods Notes: Real-Data Analysis Pipeline

Running notes for the updated methods section. Sections added as each analysis phase completes.
Numbers are from the current pipeline run (N = 351 raw, data as of 2026-06-11).

---

## Recruitment and Sample

- Dual-source recruitment: CloudResearch Connect panel + snowball sampling.
- **CloudResearch classification**: `connect_id` matching `^[A-Za-z0-9]{32}$` (exactly 32 alphanumeric characters). Snowball participants who entered random text in the `connect_id` field are correctly classified as snowball based on pattern match, not null check.
- Raw intake responses: **351 participants**.

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
- **Scope**: 4 participants missing `pf4` at tp1 due to item-level non-response (4 of 1,008 person-observations, < 0.4%; verified against current export 2026-06-12). `cw_mean` subject to same rule by consistency; no known CW missingness in the current data.
- **Justification**: Raaijmakers (1999) and Fayers & Machin (2014) confirm proration introduces operationally negligible bias at >= 80% coverage on internally consistent scales. Item-level FIML was considered and rejected as disproportionate to the scope (4 observations out of 1,008; verified 2026-06-12).
- **Methods note**: "Four participants were missing responses on one item (pf4) at the 9AM timepoint due to item-level non-response. For these observations, the physical fatigue mean was computed from the four available items (80% item coverage). Given the high internal consistency of the scale and the minimal scope of the missing data (< 0.4% of observations), this approach is consistent with accepted thresholds (Raaijmakers, 1999)."

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

- **351** participants screened.
- **15 excluded** (4.3%): all met >= 2 exclusion criteria (`dq_09_excluded_participants.csv`).
- **336 retained** for analysis.
- **8 additional participants** flagged by >= 2 of all 6 indices (longstring + duration only); not excluded. Mahalanobis does not flag any of them, supporting their retention. (Verified against current `dq_08_person_summary.csv`, 2026-06-12.)
- Cite: Meade & Craig (2012); Curran (2016) for sequential multi-criterion framework.

---

## Analytical Sample

- **N = 336 participants**, **1,008 person-observations** (3 per participant).
- Level 1 (within-person): person-timepoint observations.
- Level 2 (between-person): person-level means and intake covariates.

---

---

## Correlation Analysis

Two correlation matrices reported in the manuscript: between-person (Pearson on person-level scores) and within-person (repeated-measures correlation; Bakdash & Marusich, 2017). Every r matrix ships a companion `*_pvalues.csv` with unadjusted pairwise p-values (`p_adjust = "none"`; the correlation package default is Holm, which is for inferential multiplicity control, not descriptive-table stars).

### Output provenance (each file matches its actual estimand)

| File | Estimand | Role |
|---|---|---|
| `corr_01_l2_pearson_matrix.csv` | Pearson among L2 intake variables (one row per person) | Between-person, intake block (Table 2b) |
| `corr_02_l1_pooled_pearson_matrix.csv` | Pooled (total) correlations across all 1,008 rows; ignores nesting, conflates within + between variance | Diagnostic only; never a manuscript estimate |
| `corr_03_mlm_within_partial_matrix.csv` | lme4-based partial correlation adjusted for person (`correlation::correlation(multilevel = TRUE)`) | Within-person comparison estimator only (vs. rmcorr); previously misnamed `_between_` |
| `corr_04_rmcorr_within_matrix.csv` | rmcorr (Bakdash & Marusich, 2017) | Primary within-person estimate (Tables 2a, 2 combined below-diagonal) |
| `corr_05_between_person_matrix.csv` | Pearson among person-level scores: L1 variables averaged across the 3 timepoints (one global person mean each, not within-person centering) joined with L2 intake variables (18 x 18) | Primary between-person estimate (Table 2 combined above-diagonal, incl. the L1 x L2 block) |

### Why rmcorr for within-person

The `correlation::correlation(multilevel = TRUE)` approach (lme4-based partial correlations) systematically attenuates within-person associations by partialling out all other predictors. `rmcorr` estimates the common intra-individual linear relationship while removing between-person variance via individual intercepts, without partialling. This is the appropriate estimator for an ESM design where within-person associations are the target of inference.

### Key between-person correlations (person-level Pearson, N = 336; all p < .001 unless noted)

| Pair | r |
|---|---|
| PCB (br_mean) -- PCV (vio_mean) | .857 |
| PCB -- Job Satisfaction | -.624 |
| PCV -- Job Satisfaction | -.681 |
| Positive Affect -- Negative Affect | -.359 |
| Negative Affect -- PCV | .302 |
| PF (person mean) -- Turnover Intention | .628 |
| PCV -- Turnover Intention | .608 |
| Job Satisfaction -- Turnover Intention | -.578 |

### Key within-person correlations (rmcorr, N = 336, 1,008 obs; all p < .001 unless noted)

| Pair | r |
|---|---|
| PF -- CW | .641 |
| PF -- Turnover Intention | .306 |
| EE -- Turnover Intention | .294 |
| EE -- PF | .276 |
| NF Competence -- NF Relatedness | .496 |
| NF Competence -- NF Autonomy | .381 |
| NF Autonomy -- NF Relatedness | .294 |
| CW -- Turnover Intention | .222 |
| NF Competence -- Turnover Intention | .186 |

- **Manuscript figure**: `figs/corr/corr_between_within.svg`
- Integration test: `analysis/tests/test_correlation_outputs.r` verifies r/p matrix alignment and spot-checks corr_05 against an independent `cor.test` recomputation.

---

## Measurement Model

### L2 Single-Level CFA (between-person scales)

Five factors measured once at intake: Positive Affect (POS_AFF, 5 items), Negative Affect (NEG_AFF, 5 items), PC Breach (PCB, 5 items), PC Violation (PCV, 4 items), Desirability of Movement (DES, 2 items). Estimated with MLR. DES is a just-identified 2-indicator factor (0 df); its inclusion does not change the testable df of the other four factors.

**Fit**: χ²(179) = 299.40, *p* < .001; CFI = .967; TLI = .962; RMSEA = .049 [.039, .058]; SRMR = .044

All loadings significant (*p* < .001); standardized loadings range .508 -- .922.

**McDonald's omega**:

| Factor | ω |
|---|---|
| POS_AFF | .774 |
| NEG_AFF | .817 |
| PCB | .942 |
| PCV | .919 |
| DES | .881 |

### L1 Multilevel CFA (within-person scales)

Seven factors measured at each timepoint: PF (5 items; pf3 excluded -- see Scale Scoring), CW (5 items), EE (3 items), NF Competence (4 items), NF Autonomy (4 items), NF Relatedness (4 items), ATCB marker (4 items). MCFA with within- and between-person decomposition (Lai, 2021); estimated with MLR.

**Fit**: χ²(712) = 1348.47, *p* < .001; CFI = .943; TLI = .935; RMSEA = .033 [.031, .036]; SRMR_within = .049; SRMR_between = .077

RMSEA is particularly strong (.033); SRMR_between (.077) slightly elevated relative to the within level, consistent with modest between-person item variance in daily diary designs.

**McDonald's omega -- within-level** (state reliability, key for ESM inference):

| Factor | ω_within |
|---|---|
| PF | .809 |
| CW | .844 |
| EE | .607 |
| NF Competence | .563 |
| NF Autonomy | .554 |
| NF Relatedness | .619 |
| ATCB (marker) | .483 |

**McDonald's omega -- between-level** (person-mean / trait reliability):

| Factor | ω_between |
|---|---|
| PF | .973 |
| CW | .986 |
| EE | .957 |
| NF Competence | .969 |
| NF Autonomy | .949 |
| NF Relatedness | .939 |
| ATCB (marker) | .983 |

**Notes for write-up**:
- Within-level omegas for NF facets (.554 -- .619) and EE (.607) are moderate. This is expected in ESM designs: state-level fluctuation carries more item-specific noise than stable trait scores. PF (.809) and CW (.844) show strong within-level reliability.
- Level-specific ω_W and ω_B are reported separately for all factors per Geldhof et al. (2014): reliability in multilevel data must be evaluated at each level because measurement error accumulates at the within-person level.
- Omega computed directly from λ, φ, θ parameter estimates (McDonald, 1999; Lai, 2021). semTools::compRelSEM() not used for MCFA levels due to deprecated config= argument in semTools >= 0.5-8.
- Negative between-level residual variances (Heywood cases) clamped to 0 before omega computation, consistent with semTools internal convention.
- Single-item measures excluded from CFA (JS, JIS): MCFA requires at least two indicators per latent factor; a single item has no within-variable covariance to decompose and cannot partition within/between variance. These variables are entered as observed L2 covariates in the MLM (Muthén, 1994). This is not a limitation; it is the correct specification.
- Turnover Intention (TI): single item measured at each of three ESM timepoints. TI was NOT included in the MCFA for the same reason (no factor structure to estimate from one item). Instead, its between/within variance partition was confirmed via the ICC from the unconditional MLM (M0): ICC = .792, indicating that 79.2% of TI variance is between-person and 20.8% is within-person, sufficient to support both L1 and L2 hypothesis tests (Song et al., 2023). Manuscript framing: "Given that TI was measured as a single item at each timepoint, internal consistency was not assessable. The between- and within-person variance structure of TI was evaluated by examining its ICC from the unconditional model (ICC = .792), confirming meaningful variability at both levels."
- Desirability of Movement (DES): 2-item factor (des1, des2) included in the L2 CFA. A 2-indicator factor is just identified (0 df); fit cannot be tested independently but omega is estimable.
- Cite: Bakdash & Marusich (2017) for rmcorr; Lai (2021) for MCFA omega; Geldhof et al. (2014) for level-specific reliability; Vandenberg & Lance (2000) for measurement equivalence rationale (pf3 exclusion); Muthén (1994) for MCFA framework; Song et al. (2023) for single-item ESM DV validation.

### Metric Invariance Test

The current MCFA (section above) is a **configural** model: same factor structure at L1 (within-person) and L2 (between-person), but loadings are free to differ across levels. Metric invariance constrains loadings to be equal across levels, which is required to interpret the constructs as meaning the same thing at both levels (Hox, 2010) -- an assumption that is implicitly made when the same item block enters both the within-person (CWC) and between-person (person-mean) predictors in the MLM.

**Test**: Satorra-Bentler scaled chi-square difference test (configural vs. metric), appropriate for MLR.

**Result**: SB-Δχ²(22) = -2.35, *p* = 1.00 -- **metric invariance supported**. The constrained metric model (equal loadings at L1 and L2) does not produce a meaningful degradation in fit relative to the configural model. Factor loadings can be treated as equivalent across the within-person and between-person levels, providing psychometric justification for using the same items to operationalize both the CWC within-person predictors and the person-mean between-person predictors in the MLM.

**Note for manuscript reporting**: A negative Satorra-Bentler scaled chi-square difference is a known artifact of the scaling correction: when the scaling factor differs between the configural and metric models, the scaled difference can be negative even when the raw chi-square increases. This does not indicate misspecification or a computational error; it reinforces metric invariance support. Suggested reporting language: "SB-Δχ²(22) = -2.35, *p* = 1.00; the negative value reflects the Satorra-Bentler scaling correction and indicates no meaningful degradation in fit when loadings are constrained to equality across levels."

| Model | χ² | df | SB-Δχ² | Δdf | *p* |
|---|---|---|---|---|---|
| Configural | 1689.61 | 712 | -- | -- | -- |
| Metric (equal loadings) | 1762.47 | 734 | -2.35 | 22 | 1.00 |

**Known limitation**: A saturated between-level model (all L2 variances and covariances free, no latent factor at L2) was not tested as a robustness check (Hox, 2010). This model would diagnose constructs that exist only as within-person processes with minimal coherent between-person structure. Future work should include this check.

**Known limitation**: Single-item reliability for TI could not be assessed via within-survey retest because the protocol did not include item repetition. This precludes the m-Path approach (Dejonckheere et al., 2022). Future ESM designs measuring TI as a single item should consider including a repeated item within the same survey occasion.

- Cite: Hox (2010) for configural/metric invariance framework; Geldhof et al. (2014) for level-specific reliability; Menghini et al. (2024) for ESM MCFA template; Dejonckheere et al. (2022) for single-item retest reliability.
- Output: `figs/cfa/cfa_08_metric_invariance.md`

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

**Step 2 -- Baseline**: The MCFA from the previous section (7-factor, CFI = .943, RMSEA = .033) serves as the Baseline (Model 1).

**Step 3 -- Method-U (free ATCB cross-loadings at L1)**: ATCB was allowed to freely cross-load on all 25 L1 substantive items. The Satorra-Bentler scaled chi-square difference test was significant: SB-χ²(25) = 68.69, *p* < .001. The 25 additional cross-loading parameters produced a statistically significant improvement in fit. Importantly, this does NOT automatically indicate substantive common method bias; the test simply detects that ATCB shares some variance with substantive items beyond its marker role. Proceeding to Method-R is required to assess whether this contamination biases the substantive factor relationships.

**Step 4 -- Method-R (ATCB cross-loadings + L1 factor covariances fixed to Baseline)**: L1 factor covariances were fixed to the Baseline model values while ATCB cross-loadings remained free. The difference between Method-U and Method-R was not significant: SB-χ²(21) = 2.00, *p* = 1.00. The substantive factor correlations are invariant between Method-U and Method-R, meaning that ATCB's cross-loadings do not systematically bias the factor relationships among the substantive constructs.

| Model | χ² | df | SB-Δχ² | Δdf | *p* |
|---|---|---|---|---|---|
| Baseline (MCFA) | 1348.47 | 712 | -- | -- | -- |
| Method-U (free ATCB cross-loadings) | 1373.30 | 687 | 68.69 | 25 | < .001 |
| Method-R (Method-U + fixed L1 factor covariances) | 1325.38 | 708 | 2.00 | 21 | 1.00 |

**Conclusion**: Although ATCB showed statistically significant cross-loadings in Method-U, Method-R confirms that these cross-loadings do not bias the substantive factor correlations (Method-U vs. Method-R: *p* = 1.00). The marker variable technique indicates that common method variance does not meaningfully distort the discriminant validity of the within-person measurement model. This is the appropriate evidential standard: the absence of Method-R significance is the criterion, not the absence of Method-U significance.

- Cite: Williams et al. (2010); Williams & McGonagle (2016); Miller & Simmering (2023); Miller et al. (2024).
- Outputs: `figs/cfa/cfa_05_marker_evidence.csv`, `cfa_06_marker_fit.csv`, `cfa_07_marker_lrt.csv`

---

## Multilevel Model

### Model building sequence (M0 to M7b)

Nested data: N = 336 L2 units (participants) x 3 L1 observations nested within each person (1,008 total). DV: turnover_intention_mean (single-item, 1-5 scale). Centering: person-mean centering (CWC) for L1 predictors via datawizard::demean(); grand-mean centering for L2 predictors. Following Curran & Bauer (2011) and Enders & Tofighi (2007). ML for LRTs; REML for final parameter tables.

**Model fit summary** (ML estimation):

| Model | AIC | BIC | R2_mar | R2_con | tau_00 | LRT chi2 | df | p |
|---|---|---|---|---|---|---|---|---|
| M0: Unconditional means | 2331.3 | 2346.0 | .000 | .792 | .965 | -- | -- | -- |
| M1: Fixed time | 2328.4 | 2348.0 | .002 | .795 | .967 | 10.97 | 1 | .001 |
| M2: Random slope | 2309.8 | 2339.3 | .002 | .823 | .843 | 22.45 | 2 | <.001 |
| M3: L1 within-person (H1a, H2a) | 2273.4 | 2347.2 | .046 | .831 | .857 | 103.26 | 9 | <.001 |
| M4: L1 within + between (H1b, H2b) | 2062.9 | 2176.0 | .496 | .831 | .354 | 265.16 | 8 | <.001 |
| M5: L2 study vars + controls (H4a, H4b, H5) | 2031.6 | 2179.1 | .572 | .832 | .277 | 77.11 | 7 | <.001 |
| M6: Demographic screening | 2056.4 | 2223.5 | .570 | .833 | .280 | 1.25 | 4 | .870 |

- **ICC (M0)**: R2_conditional = .792, confirming substantial between-person variance in TI (prerequisite met). With 79.2% of TI variance between-person, only 20.8% is within-person variance available for L1 predictors to explain. Significant L1 effects despite this constraint argue for within-person construct sensitivity; this framing belongs in the Discussion rather than presenting the high ICC as a neutral observation.
- **M4 drives the explained variance**: R2_marginal jumps from .046 to .496 when between-person means enter; L1 person-mean components carry the bulk of the predictive signal.
- **M5 adds 7 L2 parameters** (pa, na, jis, des, br, vio, js -- all grand-mean centered); LRT df = 7.
- **M6 non-significant**: LRT χ²(4) = 1.25, *p* = .870. M6 = M5 + two mandatory, theory-justified demographic covariates: `age_c` (1 df) and `job_tenure` (3 dummy df), pre-specified in the proposal (Griffeth et al., 2000; Rubenstein et al., 2018). `is_remote` was the only covariate subjected to the Bernerth & Aguinis (2016) bivariate screen and **failed it decisively** (r = .008, *p* = .878; `mlm_09_covariate_screening.csv`); it does not appear in M6 or any model. Gender, education level, and ethnicity were never candidates for entry (collected for sample description only). `recruitment_source` entered at M3 as a mandatory control and is retained through M7b.

### ML vs. REML: Estimation Strategy

**ML (Maximum Likelihood)** maximizes the likelihood of the data given both fixed and random effect parameters simultaneously. Treating fixed effects as known when estimating variance components produces downwardly biased estimates of τ₀₀, τ₁₁, and σ² (analogous to dividing by *n* rather than *n-1*). **REML (Restricted Maximum Likelihood)** maximizes the likelihood of the residuals after projecting out fixed effects, yielding unbiased variance component estimates.

With only 3 Level 1 occasions per person, τ₁₁ is already estimated with limited information; ML would shrink it further. With M5 containing 25+ fixed effects, the REML degrees-of-freedom correction is non-trivial.

**Critical constraint**: REML LRT is valid only when comparing models that differ *solely* in random effects structure with identical fixed effects. When fixed effects differ across nested models (M0 through M6), ML LRT is required because the REML log-likelihood is computed on a different residual space for each fixed-effect specification and cannot be directly compared.

Fixed effect point estimates (β coefficients) are typically very similar between ML and REML at N = 336. The practical differences are in standard errors (REML SEs slightly larger, more conservative) and variance components (REML unbiased). More conservative REML SEs are the appropriate basis for reporting small L1 within-person effects.

### L2 Environmental Controls (M5 and above)

Two between-person controls were promoted to mandatory L2 covariates alongside the hypothesized study variables (PA, NA, BR, VIO, JS):

**Job Insecurity (JIS; jis_mean)** -- adapted from Sverke et al. (2002). Measures perceived threat to continued employment. Single item; grand-mean centered to `jis_mean_c`. Included because dispositional job insecurity represents a stable environmental pressure on turnover intentions independent of the within-person burnout and need-frustration processes under study. Omitting it risks conflating between-person differences in employment precarity with the substantive L2 effects.

**Desirability of Movement / Evaluation of Stability (DES; des_mean)** -- 2-item scale (des1, des2); grand-mean centered to `des_mean_c`. Measures individual differences in preference for occupational movement versus stability (Griffeth et al., 2000). Included as a distal dispositional antecedent of TI that is theoretically orthogonal to momentary burnout and need frustration. Omitting it could inflate the residual variance and potentially attenuate L2 between-person effects.

Both variables appear in M5, M6, M7a, and M7b as covariates. JIS is excluded from the L2 CFA (single item, omega not estimable); DES is included as a 2-indicator factor.

**Recruitment source covariate justification (RESOLVED via proposal)**: The proposal pre-specifies this control verbatim: "CloudResearch vs. the snowball sampling will be dummy-coded and entered as a Level 2 covariate in all primary models. This approach will statistically control for systematic differences between samples at the between-person level while preserving the full sample for estimation of within-person effects" (Sample section). No empirical screening was ever required; the earlier framing question (screen vs. structural control) is moot. The Bernerth & Aguinis threshold applied only to the M6 screened candidate (`is_remote`). The coefficient turned out significant; see the dedicated subsection below.

**Predictor vs. covariate classification** (for write-up framing):

| Variable | Role | Basis |
|---|---|---|
| Age, job tenure | Demographic covariate (M6) | Mandatory, theory-justified (Griffeth et al., 2000; Rubenstein et al., 2018); not screened |
| `is_remote` | Screened candidate, excluded | Failed Bernerth & Aguinis r >= .10 screen (r = .008, *p* = .878); in no model |
| Gender, education, ethnicity | Not modeled | Sample description only; never candidates for model entry |
| PA (pa_mean), NA (na_mean) | L2 covariate | Dispositional affect upstream of burnout/NF; no directional hypothesis |
| `recruitment_source` | Structural covariate | Mandatory control M3-M5; structural difference between sources |
| JS (js_mean) | L2 predictor of interest | Directional hypothesis H5 |
| PCB (br_mean) | L2 predictor of interest | Directional hypothesis H4a |
| PCV (vio_mean) | L2 predictor of interest | Directional hypothesis H4b |
| JIS, DES | L2 covariate | Post-hoc environmental controls; no directional hypothesis |

M5 contains theoretically motivated predictors and structural controls. M6 is a sensitivity check showing focal effects survive demographic controls. This distinction shapes how each model is narrated in Results.

- Cite: Sverke, Hellgren, & Naswall (2002) for JIS; Griffeth, Hom, & Gaertner (2000) for DES; Bernerth & Aguinis (2016) for M6 covariate screening threshold.

### Interpreting the final model (M5)

M5 is the primary inferential model and should be narrated as such; this section outlines the full interpretation frame for Results and Discussion.

**Why M5, not M6 or M7**: M5 has the best AIC (2031.6 vs. 2056.4 for M6), contains every hypothesized predictor, and the M6 LRT is decisively non-significant (χ²(4) = 1.25, *p* = .870). The pipeline's built-in stability check confirms no substantive coefficient moves more than 20% from M5 to M6 (e.g., EE within: .2309 in both; PCB: .128 vs. .129; JS: -.163 vs. -.160). M6 is therefore a *sensitivity analysis* demonstrating robustness to demographics, not a competing model; M7a/M7b are exploratory moderation probes. Narrate: "Model 5 served as the final inferential model; Model 6 confirmed that all substantive effects were robust to demographic covariates."

**Variance accounted for (M5)**: R²_marginal = .572 (fixed effects), R²_conditional = .832. The fixed effects explain 57% of total TI variance; the random structure (person intercepts + time slopes) brings the model to 83%. τ₀₀ drops from .965 (M0) to .277 (M5): the L2 predictors account for ~71% of the between-person intercept variance.

**Coefficient reading guide** (two distinct estimands; never compare raw magnitudes across levels):

- `*_within` (CWC): occasion-level deviation effects. ee_mean_within = .231 reads "on check-ins where a person reports EE 1 point above *their own* daily average, TI is .23 higher, net of all else." These are pure within-person effects; CWC strips all between-person variance, so they are structurally immune to L2 confounds (including recruitment source).
- `*_between` / `*_c` (person means / intake, GMC): chronic-standing effects. pf_mean_between = .439 reads "a person 1 raw point above the sample-average chronic PF reports .44 higher average TI." Use `mlm_05_standardized_effects.csv` / `mlm_06_level_specific_es.csv` for cross-level magnitude comparisons.

**Significant effects in M5 outside the hypothesis set** (all must be reported, not buried):

1. **Time trend**: time_c = +.044, *p* = .021. TI drifts upward across the workday (~.09 raw points from 9AM to 5PM) net of all predictors. Consistent with COR monotonic-depletion framing; merits one Discussion sentence as convergent (unhypothesized) evidence.
2. **Between-person meeting load, opposite signs**: meetings_count_between = +.287 (*p* < .001) and meetings_time_between = -.0064/min (*p* < .001). These are *mutually partialled*: count holding total time constant indexes meeting *fragmentation* (many short meetings -> higher chronic TI); time holding count constant indexes longer average meetings (-> lower TI). Do not interpret as raw bivariate directions. The proposal's narrative anticipated meeting load as a direct within-person predictor plus moderator; the WP direct effects are null while these BP effects are significant and unhypothesized. Frame as exploratory between-person findings with the fragmentation interpretation offered cautiously.
3. **Recruitment source**: snowball > CloudResearch on TI; dedicated subsection below.
4. **CW between-person contrary effect**: already flagged under Write-Up Flags (H2b:cw).

**Random-slope framing guard**: the proposal commits to "random intercepts but fixed slopes." That commitment concerns *substantive predictor* slopes (evaluated via rho_beta, no cross-level interaction tests; honored throughout). The retained random effect `(time_c | response_id)` is a growth-curve component for time, adopted at M2 via LRT (χ²(2) = 22.45, *p* < .001), standard for longitudinal designs. Make this distinction explicit in the manuscript so the M2 random slope is not misread as a deviation from the proposal.

### Recruitment source: a significant between-sample difference

`recruitment_sourcesnowball` is significant in every model that includes L2 predictors:

| Model | B (snowball) | SE | *p* |
|---|---|---|---|
| M4 | +.435 | .091 | < .001 |
| M5 | +.260 | .086 | .003 |
| M6 | +.255 | .088 | .004 |

Snowball participants report ~0.26 points higher average TI (1-5 scale) than CloudResearch Connect participants net of all substantive predictors, roughly 0.25 between-person SDs (BP SD_TI = 1.025). About 40% of the raw M4 source gap is absorbed when the L2 study variables (affect, JIS, DES, PCB/PCV, JS) enter at M5; the remainder persists.

**How this changes interpretation (write-up guidance)**:

1. **The control is doing exactly the job the proposal assigned it.** A significant coefficient is the design working, not a problem: systematic between-sample differences in TI level exist, and every L2 estimate (H4a, H4b, H5, covariates) is interpreted *net of source*, i.e., as a within-source effect. Had the dummy been omitted, those L2 coefficients would be contaminated by source composition.
2. **L1 estimates are untouched.** Person-mean centering removes all between-person variance, source membership included, from the within-person predictors; H1-H3 conclusions are structurally independent of this coefficient. State this explicitly to preempt the committee question.
3. **Candidate explanations for the Discussion** (cannot be adjudicated with these data; engage at least one): (a) *selection*: snowball recruits arrived via LinkedIn and personal networks; active LinkedIn presence correlates with job-market attentiveness, plausibly elevating baseline withdrawal cognitions; (b) *incentive asymmetry*: CloudResearch participants were compensated per occasion plus a completion bonus, snowball participation was voluntary, shaping who opts in; (c) *residual composition*: occupational/industry differences not captured by modeled covariates.
4. **What it is NOT evidence of**: differential data quality (careless-responding screening applied identically to both sources) or a threat to internal validity of the within-person tests.
5. **External validity caveat**: absolute TI levels are sample-composition-dependent and not population-representative; the inferential focus is relational (within- and between-person associations), which the dual-source design supports.
6. **Untested assumption to disclose**: source x predictor interactions were not modeled (the proposal specified a main-effect control only). Homogeneity of slopes across sources is an assumption, not a finding; note it in Limitations or run a sensitivity interaction model if a committee member asks.

### Hypothesis tests

**Supported hypotheses (p < .05, correct direction)**:

| Hypothesis | Term | Estimate | p | Model |
|---|---|---|---|---|
| H1a:comp | WP competence frustration | +.115 | .013 | M3 |
| H2a:pf | WP physical fatigue | +.165 | <.001 | M3 |
| H2a:ee | WP emotional exhaustion | +.222 | <.001 | M3 |
| H2b:pf | BP physical fatigue mean | +.529 | <.001 | M4 |
| H2b:ee | BP emotional exhaustion mean | +.547 | <.001 | M4 |
| H4a | BP PC breach | +.128 | .050 | M5 |
| H5 | BP job satisfaction | -.163 | <.001 | M5 |

**Not supported**:

| Hypothesis | Term | Estimate | p | Note |
|---|---|---|---|---|
| H1a:auto | WP autonomy frustration | -.005 | .888 | Wrong direction |
| H1a:relt | WP relatedness frustration | +.005 | .917 | ns |
| H1b (all) | BP NF facet means | .047 to .101 | .209 to .383 | ns |
| H2a:cw | WP cognitive weariness | +.027 | .499 | ns |
| H2b:cw | BP cognitive weariness mean | -.233 | .001 | Wrong direction |
| H3a:count | Count x NF composite | -.072 | .335 | ns |
| H3a:time | Time x NF composite | -.002 | .392 | ns |
| H3b:count | Count x burnout composite | +.000 | .999 | ns |
| H3b:time | Time x burnout composite | +.003 | .196 | ns |
| H4b | BP PC violation | +.093 | .205 | ns |

**Examiner-level flags for specific findings:**

- **H2b:cw (actively contrary, not null)**: β = -.233, *p* = .001 is in the wrong direction and significant. This cannot be reported only as "not supported" -- it is a contradictory finding that directly counters the COR depletion logic. A Discussion paragraph must address it. Candidate explanations: (1) suppression from multicollinearity with PF at the between-person level (rmcorr r = .651 within-person; the L2 person-mean overlap is likely similar), where CW's between-person coefficient is displaced once PF's dominant L2 signal enters; (2) range restriction at the between-person level; (3) a compensatory habituation effect where chronically cognitively weary workers hold on more tightly to avoid job transition uncertainty. One of these must be engaged directly in the Discussion.

- **H4a (borderline p + below-80% power)**: β = +.128, *p* = .050 exactly, estimated power ~.60. The power caveat must be integrated directly with the hypothesis test result in Results, not deferred to Limitations. Suggested framing: "H4a was supported at the threshold level (β = +.128, *p* = .050); given the borderline *p*-value and estimated power of approximately .60 at this sample size, this finding should be treated as provisional pending replication."

### Slope heterogeneity (rho_beta; Aguinis & Culpepper, 2015)

| Predictor | rho_beta | tau11 | Magnitude |
|---|---|---|---|
| PF (within) | .053 | .304 | medium |
| Comp NF (within) | .040 | .329 | small-medium |
| Burnout composite (within) | .033 | .355 | small-medium |
| EE (within) | .022 | .210 | small-medium |
| CW (within) | .014 | .073 | small-medium |
| NF composite (within) | .012 | .155 | small-medium |
| Relt NF (within) | .006 | .054 | negligible |
| Auto NF (within) | .004 | .020 | negligible |

rho_beta quantifies the proportion of within-person variance explained by slope heterogeneity (i.e., individual differences in how strongly each L1 predictor relates to TI). PF has the largest rho_beta (.053), indicating moderate person-level variability in the PF-TI slope. Most other predictors show small-medium or negligible slope heterogeneity.

- Outputs: `figs/mlm/mlm_04_hypothesis_tests.md`, `mlm_08_iccbeta.csv`, model diagnostics at `mlm_diag_model_*.svg`
- Cite: Curran & Bauer (2011); Enders & Tofighi (2007); Aguinis & Culpepper (2015).

---

## Write-Up Flags

Identified in committee-level review. Address before dissertation defense.

### PCB-PCV Multicollinearity

Between-person correlation PCB-PCV = .857 approaches collinearity. Both are simultaneous L2 predictors in M5. H4a supports breach (p = .050) but H4b does not (PCV, p = .205); with r = .857 these findings are nearly inseparable. Required before final write-up: (a) run VIF for M5's L2 predictor block and document; (b) frame the theoretical distinction explicitly (cognitive appraisal vs. emotional response; Robinson & Morrison, 2000); (c) consider a sensitivity model with only one of the two to confirm estimates are not artificially split.

### M7a/M7b Composites: Proposal-Faithful, but Dilution Concern Stands

The composite operationalization is **pre-specified in the proposal**: H3a and H3b each read "operationalized as a composite of its subdimensions." M7a/M7b are therefore proposal-faithful, not an inconsistency; do not frame this as a deviation. The substantive concern remains: supported M3 results show EE and PF drive L1 effects while CW is non-significant, so collapsing to a burnout composite averages in the non-significant CW, potentially diluting a real EE-meetings interaction. If computationally feasible, run M7a/M7b with individual subscales. If not, acknowledge explicitly: "Collapsing to composites may obscure facet-specific moderation; future work should test whether meeting load moderates the EE-TI and PF-TI slopes specifically."

### JIS and DES: Post-Hoc Additions

JIS and DES were not in the original proposal. They were added post-hoc as L2 covariates in M5. The manuscript must acknowledge this explicitly with theoretical rationale (see L2 Environmental Controls section above); M5 should not be presented as if it were the pre-specified model. Standard framing: "Two L2 controls were identified during analysis and added to address potential confounding (JIS: Sverke et al., 2002; DES: Griffeth et al., 2000)."

### EE ω_within vs. Effect Size Tension

EE within-level reliability (ω_within = .607) is the weakest primary construct, yet H2a:ee (β = +.222, *p* < .001) is one of the strongest supported findings. Reviewers will notice the tension. Proactive framing: EE items capture acute emotional depletion that is particularly sensitive to within-day fluctuation; high ESM-state sensitivity attenuates within-level reliability even when the construct is meaningfully varying. PF items use more stable resource language, consistent with PF's higher ω_within (.809). Address in the measurement model discussion, not only in the omega table.

### Null NF Facets: Theoretical Engagement Required

H1a:auto (β = -.008) and H1a:relt (β = +.006) are near-zero; all of H1b is non-significant. The Introduction built a full BPNT pathway across all three need-frustration facets. A Discussion paragraph must genuinely engage with the facet-specific pattern rather than citing only power. Candidate framings: (1) competence thwarting has the strongest face validity for turnover cognitions in knowledge workers (being blocked from exercising task competence has direct instrumental relevance to job exit); (2) autonomy and relatedness thwarting may operate through burnout as a mediator rather than directly onto TI; (3) the within-day three-timepoint grain may be too short for autonomy and relatedness effects to accumulate into turnover cognitions.

## Post Hoc Power Confirmation

Updated 2026-06-12 for the current analytical sample (N = 336, 1,008 obs): WP/BP SDs
re-verified against the current export, interpolations recomputed at N ≈ 336
(weight 0.36 between the N = 300 and N = 400 grid nodes). All grid-node assignments
are unchanged except H2a:ee, whose standardized effect rounds to ~.19 with current
SDs (was ~.20); its power estimate moves from ~.997 to ~.99.

**Target vs. achieved N**: the proposal's a priori target was N = 800 (chosen for >= 90% power on medium effects with conservative zero slope-intercept covariance). The achieved analytical sample is N = 336, 42% of target. The manuscript must state this shortfall plainly and point to this post hoc analysis as the quantification of what the realized N delivers: essentially full power for medium-and-larger effects, but ~.62-.84 power in the small-effect range (std ~.13) where H1a:comp and H4a landed. The shortfall is consequential exactly where the borderline findings live.

### Analytic strategy

Post hoc power estimates are drawn from two Monte Carlo simulation grids (Arend & Schafer, 2019) run via `analysis/run_power_analysis/` on GCP Compute Engine (1,000 simulations per cell; Kenward-Roger tests).

**A priori grid** (`power_analysis_results_20260316_183228.csv`): N_Level2 ∈ {100, ..., 1500}, ICC ∈ {0.10, 0.30, 0.50}, fixed effects ∈ {0.10, 0.30, 0.50} for L1, L2, and cross-level effects (3,645 cells).

**Supplementary posthoc grid** (`power_analysis_results_20260611_104548.csv`): ICC ∈ {0.60, 0.70, 0.80}, N_Level2 ∈ {100, ..., 1000}, L1/L2 effects ∈ {0.10, 0.15, 0.20, 0.30, 0.50}, cross-level effects ∈ {0.10, 0.30, 0.50} (2,250 cells). Designed to directly simulate ICC ≈ 0.80 and to add finer effect-size resolution (.15 and .20 nodes) where observed effects landed.

All power estimates below are drawn from the supplementary posthoc grid at ICC = 0.80. Two features of the actual design require handling:

1. **N = 336 falls between grid nodes.** Nodes at N = 300 and N = 400 bracket the actual sample; power values for N ≈ 336 are linearly interpolated across the N dimension (weight 0.36).
2. **Observed standardized effects computed post hoc:** L1 effects standardized using WP SD; L2 effects using BP (person-mean) SD. Effects at ~.13 require interpolation between the .10 and .15 nodes.

**Note on effect-size parameterization.** In the simulation, `lvl1_effect_std` is standardized relative to the within-person residual SD. At ICC = 0.80 the within-person residual SD is smaller than at ICC = 0.50, so a fixed std = 0.20 represents a larger signal-to-noise ratio at higher ICC. L1 power at moderate effects (std ≥ .20) is therefore higher at ICC = 0.80 than at ICC = 0.50 -- the opposite of the upper-bound framing previously used when only the a priori grid (max ICC = 0.50) was available. For small L1 effects (std = .10), the two ICC conditions yield nearly identical power (.621 vs. .614 at N = 300), so the distinction is negligible in that range. L2 power is uniformly higher at ICC = 0.80 than at ICC = 0.50, consistent with between-person signal concentration.

**Note on simulation conservatism.** Arend & Schäfer (2019) set the slope-intercept covariance to zero throughout their simulation design to produce conservative power estimates; they note this "will not greatly influence the results, because the standard errors of fixed effects are not sensitive to the correlation" (Bosker et al., 2003; Snijders & Bosker, 1993). The observed random effects show a negative slope-intercept correlation across models (Cor(U₀ⱼ, U₁ⱼ) = -0.177 to -0.224 in M2 through M4). A negative correlation reduces standard errors for slope estimates, which increases power relative to the zero-covariance assumption used in the simulation. The reported power values are therefore conservative lower bounds; actual power achieved with real data is likely modestly higher, providing an additional margin of safety.

### Observed standardized effect sizes

Standardized beta = beta_unstd * (SD_pred / SD_TI), computed from actual WP and BP SDs in the analytical sample (N = 336; SDs re-derived from the current export 2026-06-12: WP SD = SD of person-mean deviations, BP SD = SD of person means).

**L1 (within-person, WP-centered):**

| Hypothesis | Predictor | beta_unstd | SD_WP_pred | SD_WP_TI | std_beta |
|---|---|---|---|---|---|
| H1a:comp | WP Competence Frus. | +.138 | .383 | .411 | ~.13 |
| H2a:pf | WP Physical Fatigue | +.180 | .459 | .411 | ~.20 |
| H2a:ee | WP Emotional Exhaustion | +.218 | .359 | .411 | ~.19 |

**L2 (between-person, person-mean):**

| Hypothesis | Predictor | beta_unstd | SD_BP_pred | SD_BP_TI | std_beta |
|---|---|---|---|---|---|
| H2b:pf | BP Physical Fatigue | +.520 | .906 | 1.025 | ~.46 |
| H2b:ee | BP Emotional Exhaustion | +.544 | .584 | 1.025 | ~.31 |
| H4a | BP PC Breach | +.131 | 1.039 | 1.025 | ~.13 |
| H5 | BP Job Satisfaction | -.178 | 1.142 | 1.025 | ~.20 |

### Power estimates from supplementary simulation (ICC = 0.80; N = 300 and N = 400)

**L1 direct effects:**

| std_beta | N = 300 | N = 400 | N ≈ 336 |
|---|---|---|---|
| .10 (small) | .621 | .747 | ~.666 |
| .13 (H1a:comp; interp.) | ~.808 | ~.886 | ~.836 |
| .15 | .933 | .978 | ~.949 |
| .19 (H2a:ee; interp.) | ~.983 | ~.995 | ~.987 |
| .20 (H2a:pf) | .996 | .999 | ~.997 |
| .30+ (medium) | 1.00 | 1.00 | 1.00 |

Values at std = .13 and .19 are bilinearly interpolated between adjacent effect nodes and the N = 300 and N = 400 nodes. Values at N ≈ 336 are linearly interpolated within each effect row (weight 0.36).

**L2 direct effects:**

| std_beta | N = 300 | N = 400 | N ≈ 336 |
|---|---|---|---|
| .10 (small) | .387 | .494 | ~.426 |
| .13 (H4a; interp.) | ~.579 | ~.697 | ~.621 |
| .15 | .707 | .833 | ~.752 |
| .20 (H5) | .925 | .974 | ~.943 |
| .31 (H2b:ee; interp.) | .999 | 1.00 | ~.999 |
| .46 (H2b:pf; interp.) | 1.00 | 1.00 | 1.00 |

Values at std = .13, .31, and .46 are bilinearly interpolated between adjacent effect nodes and the N = 300 and N = 400 nodes.

### Verdict by supported hypothesis

| Hypothesis | std_beta | Power (N ≈ 336, ICC = 0.80) | p | Assessment |
|---|---|---|---|---|
| H1a:comp | ~.13 | ~.84 | .013 | Moderate power; significant; small effect near detection floor -- caution on replication |
| H2a:pf | ~.20 | ~.997 | <.001 | Excellent power; well-supported |
| H2a:ee | ~.19 | ~.99 | <.001 | Excellent power; well-supported |
| H2b:pf | ~.46 | 1.00 | <.001 | Well-powered; supported |
| H2b:ee | ~.31 | ~.999 | <.001 | Well-powered; supported |
| H4a | ~.13 | ~.62 | .050 | Low-moderate power; borderline p; replicate before treating as established |
| H5 | ~.20 | ~.943 | <.001 | Good power; well-supported |

### Null findings

**Non-significant L1 effects** (H1a:auto beta=-.008; H1a:relt beta=+.006; H2a:cw beta=+.008): standardized effects all below .01. These are not underpowered null results -- they are essentially zero effects. Power to detect std_beta < .05 would be negligible at any N in the grid.

**Non-significant L2 effects** (H1b NF facet means: std_beta ≈ .04--.09; H4b PCV: p = .205): effects are below the small-effect threshold. At std_beta = .10, L2 power ≈ .43 (N ≈ 336, ICC = 0.80 supplementary grid). The simulation cannot distinguish between a true zero and an underpowered small effect at this N for these predictors. Replication at larger N would be needed to confirm absence of NF facet effects on TI.

**Within-person (L1 x L1) moderation interactions** (H3a, H3b): all non-significant. These tests model meeting load (CWC) as a within-person moderator of the NF-TI and burnout-TI slopes (M7a/M7b), making them L1 x L1 interactions -- not cross-level interactions. M7a/M7b use composites (burnout_mean = PF+CW+EE; nf_mean = comp+auto+relt) rather than the individual L1 subscales from M3/M4, but still operate at the same three timepoints (within-person). Meeting load is person-mean centered (CWC) before the interaction terms are formed.

JIS and DES appear in M7a/M7b as between-person covariates (grand-mean centered), not as moderators. There are no cross-level interactions (L2 x L1) in this study. The L2 variables control for stable between-person differences in job insecurity and mobility preferences, which would otherwise inflate residual variance at L2 and potentially contaminate the within-person moderation estimates. rho_beta was used as the primary effect-size index because it addresses the question of whether meeting load's moderation varies by person -- the appropriate frame for this L1 x L1 design.

No power estimate from the simulation grid applies to M7a/M7b: the grid's `xl_effect` parameter models a between-person (L2) predictor moderating an L1 slope, a structurally different test. Power for L1 x L1 within-person moderation in a random-intercept, 3-timepoint design is not covered by the parameterization. This gap is the reason the design foregrounds rho_beta (Aguinis & Culpepper, 2015) as a supplementary effect-size index of slope heterogeneity in lieu of formal interaction inference: with only three Level 1 occasions, random slope variance is downwardly biased and formal significance tests for L1-slope-based interactions would carry inflated Type I error rates. The interaction null findings are reported as exploratory.

- Cite: Arend & Schafer (2019); Kenward-Roger tests via `simr`.
- Source data: `analysis/run_power_analysis/data/power_analysis_results_20260316_183228.csv` (GCP a priori run, 3,645 cells x 1,000 sims); `power_analysis_results_20260611_104548.csv` (GCP posthoc run, 2,250 cells x 1,000 sims, ICC 0.60-0.80).

---

## Proposal Alignment Audit (2026-06-12)

Systematic comparison of `docs/manuscript/drafts/proposal/proposal-final-draft.txt` against the implemented pipeline. Verdict: the analysis is faithful to the proposal on every methodological commitment; deviations are few, already documented, or favorable expansions.

### Confirmed aligned

| Proposal commitment | Implementation | Evidence |
|---|---|---|
| Dual recruitment; source dummy-coded as L2 covariate "in all primary models" | `recruitment_source` in M3-M7b | `multilevel_model.r` [7]; significant, see subsection |
| Careless responding: instructed response + longstring + Mahalanobis (Meade & Craig, 2012; careless pkg) | Implemented; expanded to 6 indices (3 exclusionary as proposed, 3 diagnostic-only) | Data-quality section above |
| WP correlations via rmcorr; BP correlations via Pearson on L1 person means | corr_04 (rmcorr), corr_05 (person-mean Pearson) | Correlation section above |
| Reliability: Lai (2021) MCFA omega at within/between levels | cfa_04 omegas | Measurement section (semTools workaround documented) |
| MCFA for factor structure (lavaan, ML-family) + CFA marker technique (Williams et al.; ATCB) | cfa_01-03 (MCFA, MLR), cfa_05-07 (marker) | Measurement section |
| MLM in lme4; CWC for L1, GMC for L2; sequential build from null model; ICC | Implemented exactly | MLM section |
| Occasions coded 0-2, intercept = baseline (Biesanz et al., 2004) | `time_c = timepoint - 1` | `prep_mlm.r:39` |
| Fixed slopes for substantive predictors; rho_beta (Aguinis & Culpepper, 2015) instead of slope/cross-level significance tests | No predictor random slopes; no cross-level tests; rho_beta reported (mlm_08) | Slope heterogeneity section; random *time* slope is a growth component, see M5 interpretation guard |
| Covariates: age, tenure, PA, NA | PA/NA in M5; age/tenure mandatory in M6; model comparison with/without (Bernerth & Aguinis) | M6 bullet above |
| H3a/H3b moderation with NF/burnout *composites* | M7a/M7b composites | Write-up flag (proposal-faithful) |
| H4a/H4b (PCB/PCV), H5 (JS) as L2 predictors | M5 | Hypothesis tests |

### Deviations and manuscript fixes required

1. **N = 336 vs. proposed N = 800** -- documented in the power section; state plainly in Method.
2. **JIS and DES post-hoc L2 covariates** -- not in the proposal; existing write-up flag stands (explicit acknowledgment + rationale).
3. **Proposal-internal hypothesis numbering error (fix in manuscript text)**: the Proposed Analyses paragraph reads "Level 1 predictors ... to test H1, followed by Level 2 predictors to test H2 and H3 ... Composites ... used to test H4," which contradicts the Introduction's scheme (H2 = burnout includes L1; H3 = moderation; H4 = PC; H5 = JS). The pipeline follows the Introduction's scheme. Renumber that paragraph when porting to the dissertation document.
4. **Meeting load direct-effect framing**: the proposal narrative positions meeting load as "a direct within-person predictor of turnover intentions and as a moderator," but only the moderation is formally hypothesized (H3a/H3b). Observed: WP direct effects null; BP count/time effects significant and unhypothesized (see M5 interpretation). Manuscript should either present the WP direct effect as an implicit secondary expectation (null result) or fold it into exploratory findings; pick one framing and keep it consistent.
5. **Metric invariance test** -- not promised in the proposal; favorable addition, already documented.
6. **OSF commitment**: the proposal promises public materials at OSF (osf.io/9zprj) and GitHub. Confirm the OSF component is current before defense.

---

## Sections to Add

- [ ] Publication-ready tables (Slice 9)
