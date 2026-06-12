# Table Notes: Reading and Interpreting the Publication Tables

Companion to `../METHOD_NOTES.md`. That file covers method decisions, provenance, and
result-level interpretation; this file is strictly about **what each table shows and how to
read the data out of it** while drafting the manuscript. Every claim traces to a pipeline
output (named per table). All tables follow NCSU ETD + APA 7 conventions: three horizontal
rules, bold table number, italic title ending in a period, em dash for structurally absent
cells, probability notes as *p* < .05 / .01 / .001 stars.

Sample for all tables: N = 336 participants, n = 1,008 person-observations (3 per person).

---

## Table 1. Demographics (`table_01_demographics.docx`)

**What it shows**: Person-level (N = 336) categorical counts/percentages and continuous
M/SD for the retained analytical sample. Source: cleaned export via gtsummary
(`eda_10_table1_*.csv`).

**How to read it**: Straight frequency table; no inference. The recruitment row is the one
modeling-relevant entry (CloudResearch 255 / 75.9%, snowball 81 / 24.1%) since
`recruitment_source` is a covariate in every primary model.

**What the data say**: Working-age sample (M_age = 38.3, SD = 9.8, range 18-70), gender
near parity (50.9% women / 47.3% men / 1.5% non-binary), 71.1% White, educated (72.0%
bachelor's or higher), majority remote (56.5%).

**Manuscript use**: One Method paragraph. Lead with employment screen (18+, employed
30+ hrs/week, US-based), then composition, then the source split with a forward pointer to
the recruitment-source coefficient in the Results (snowball participants report higher
average TI; see Table 4 notes below).

**Caveats**: Educated/remote skew bounds generalizability to knowledge-type work. Gender,
ethnicity, and education appear here for description only; they are in no model (see
METHOD_NOTES, M6 bullet).

---

## Table 2a. Within-Person (L1) Descriptives and Correlations (`table_02a_l1_correlations.docx`)

**What it shows**: The L1 variable block (PF, CW, EE, NF facets, meetings, TI): M, SD
(observation-level, n = 1,008), ICC, ω_within, and the lower-triangle **repeated-measures
correlation** matrix (rmcorr; Bakdash & Marusich, 2017). Sources: `eda_04`, `eda_15_icc_table`,
`cfa_04_omega`, `corr_04_rmcorr_within_matrix`.

**How to read it**:
- Every correlation is *within-person*: between-person variance is removed via per-person
  intercepts before estimating the common intra-individual association. r = .31 for PF-TI
  reads "on occasions when a person is more physically fatigued than their own average,
  their TI is higher than their own average."
- The **ICC column** is the variance split: ICC = .69 for PF means 69% of PF variance is
  between people, 31% is the within-day fluctuation these correlations live in.
- The **ω column** is within-level (state) reliability; em dash = single item (TI) or
  structurally inapplicable (meeting counts).
- Em dash on the diagonal is structural (a variable's correlation with itself is not an
  estimate).

**What the data say** (key cells):
- Burnout coheres within persons: PF-CW = .64 is the largest cell in the matrix; PF-EE = .28,
  CW-EE = .23.
- Depletion-withdrawal coupling exists within a single workday: TI with PF .31, EE .29,
  CW .22, competence frustration .19 (all *p* < .001). This matrix is the existence proof
  for the dissertation's central phenomenon before any model.
- NF facets intercorrelate (.29-.50) but autonomy and relatedness barely touch TI
  (.10, .10), previewing the facet-specific MLM results.
- Meeting load is behaviorally coherent (count-time = .73) but psychologically weak within
  persons (TI rs = .06, .09).
- ATCB row is uniformly near zero (|r| <= .06): the marker behaves as designed.
- ICCs run .59-.91; every substantive variable retains a meaningful within-person share
  (21-41%), justifying the ESM design. TI's ICC of .79 means the within-day pool for L1
  prediction is 21% of total variance: small but real.

**Manuscript use**: The primary descriptive table for the Results opening. Narrate the
existence-proof point and the burnout-vs-NF coherence contrast; let the table carry the
numbers.

**Caveats**: ω_within of .55-.62 for NF facets and EE means within-person rs involving
those variables are attenuated by measurement error; do not over-interpret rank order
among them.

---

## Table 2b. Between-Person (L2) Descriptives and Correlations (`table_02b_l2_correlations.docx`)

**What it shows**: Intake variables (PA, NA, PCB, PCV, JS, JIS, DES): M, SD (N = 336),
ω from the single-level CFA, and lower-triangle Pearson correlations. Sources: `eda_04`,
`cfa_04_omega`, `corr_01_l2_pearson_matrix`.

**How to read it**: Ordinary Pearson correlations among once-measured person-level scores;
no nesting issues. ω column from the L2 CFA (MLR); em dash for single items (JS, JIS).

**What the data say**:
- The psychological-contract cluster dominates: PCB-PCV = .86, and JS sits at -.62/-.68
  with the two. Breach, violation, and (dis)satisfaction form one tight evaluative complex
  around the employment relationship.
- PA-NA = -.36: moderately bipolar, as expected for trait affect.
- NA correlates with PCV (.30): negative affectivity colors violation feelings, part of the
  rationale for controlling affect in M5.

**Manuscript use**: Pairs with Table 2a in the Results opening. The .86 PCB-PCV cell is the
table's headline: cite it when explaining why H4a and H4b verdicts must be read jointly
(see METHOD_NOTES, PCB-PCV multicollinearity flag).

**Caveats**: These correlations include no L1 information; the L1 x L2 relationships live
only in the combined Table 2.

---

## Table 2 (combined). Full Descriptives and Correlations, Landscape (`table_02_combined_correlations.docx`)

**What it shows**: All 18 variables in one split-diagonal matrix: **below diagonal =
within-person rmcorr** (L1 x L1 only), **above diagonal = between-person Pearson on person
means** (corr_05: L1 variables averaged over the 3 timepoints, joined with intake L2
variables). M, SD, ICC columns on the stub side. Landscape, 9 pt.

**How to read it**:
- Pick a pair, decide which question you are asking. "Do these co-fluctuate within a day?"
  -> below diagonal. "Do chronic standings co-vary across people?" -> above diagonal.
- The **L1 x L2 rectangle** (e.g., PF person-mean x JS) exists only above the diagonal;
  below it is structurally empty (em dash): an intake variable has no within-person
  fluctuation to correlate.
- Cells where the same pair appears on both sides give the trait/state contrast directly:
  PF-TI is .63 above vs. .31 below; the between-person association is roughly double the
  within-person one for the burnout-TI pairs.

**What the data say** (beyond 2a/2b): the cross-level rectangle. Chronic PF tracks TI at
.63, PCV at .61, JS at -.58, all of the same order as the contract cluster's internal
correlations: chronic momentary depletion (averaged states) is as tightly bound to
withdrawal as the classic evaluative attitudes are. That equivalence is a quotable
descriptive result.

**Manuscript use**: Either the single comprehensive correlation table (landscape page) or
an appendix behind the 2a/2b pair; the committee can choose. Both framings are prepared;
do not include both 2a/2b and the combined table in the main text (redundant).

**Caveats**: The above-diagonal estimates for L1 variables are Pearson on 3-occasion means;
with only 3 occasions, person means carry sampling noise (though ω_between = .94-.99 says
they are highly reliable here). Type I inflation from N = 336 pairwise tests is handled by
reporting unadjusted p stars and saying so in the note.

---

## Table 3. CFA Results (`table_03_cfa_results.docx`)

**What it shows**: Panel A = fit indices for both measurement models (L2 single-level CFA;
L1/L2 MCFA). Panel B = standardized loadings in factor-as-column layout (items as rows,
factors as columns, loading in the on-factor cell, blank elsewhere). Sources: `cfa_01_fit`,
`cfa_02_loadings_l2`, `cfa_03_loadings_l1`.

**How to read it**:
- Panel A row for the L2 CFA: χ²(179) = 299.40, CFI = .967, TLI = .962, RMSEA = .049
  [.039, .058], SRMR = .044. MCFA row: χ²(712) = 1348.47, CFI = .943, TLI = .935,
  RMSEA = .033 [.031, .036], SRMR_within = .049, SRMR_between = .077. Em dash where an
  index is undefined for a model type.
- Panel B: read down a column to see a factor's indicators; a clean column (no off-column
  entries) is the discriminant-validity picture. The note states all loadings *p* < .001,
  so significance columns are omitted by design (full detail in Appendix A).

**What the data say**: Both models meet conventional cutoffs (CFI >= .94, RMSEA <= .05);
RMSEA .033 for the MCFA is the standout. L2 standardized loadings span .508-.922. The
factor structure holds when within/between variance is decomposed, the precondition for
interpreting the same constructs at both levels of the MLM.

**Manuscript use**: The measurement Results paragraph cites Panel A once, then points to
Panel B for structure and Appendix A for full psychometric detail. SRMR_between = .077
gets one sentence (modest between-level item variance, typical for diary designs).

**Caveats**: DES is just-identified (2 indicators, 0 df): its fit is untestable, only its
loadings/omega are informative. ATCB sits in Panel B as the marker, not a substantive
factor; its role is documented in Appendix B.

---

## Table 4 (Strategy 1). Final Model Coefficients + Fit Progression (`table_04_s1_m5_focal.docx`)

**What it shows**: The **primary results table**. M5 fixed effects with B, SE, β
(standardized), and *p*, grouped under Within-Person (L1, CWC) / Between-Person (L2, GMC) /
Variance Components subheadings, followed by a compact M0-M6 fit panel (AIC, R²m, R²c,
ΔR²m, LRT χ² with stars). Sources: `mlm_02_fixed_effects` (REML), `mlm_05_standardized_effects`,
`mlm_01_model_comparison`, `mlm_07_delta_r2`.

**How to read it**:
- L1 rows are person-mean-centered: the coefficient is the within-person, occasion-level
  effect, structurally free of all between-person confounding.
- L2 rows are grand-mean-centered person means / intake scores: chronic-standing effects,
  net of every other L2 term *and* recruitment source.
- β rescales each B by the level-appropriate SDs; use β for magnitude talk, B for raw-scale
  talk. Never compare a raw L1 B with a raw L2 B.
- The fit panel's ΔR²m column is the marginal-variance increment per step; the LRT column
  is the formal test of that step.

**What the data say** (M5, REML):
- Within-person: EE (B = .231***), PF (.177***), competence frustration (.120**) predict
  momentary TI; CW, autonomy, relatedness, and both meeting variables do not.
- Between-person: chronic PF (.439***) and EE (.391***) dominate; chronic CW is significant
  *negative* (-.130, p = .0497; contrary finding, see METHOD_NOTES flag); JS (-.163***);
  PCB at the threshold (.128, p = .050); PCV ns (.093, p = .205).
- Time: +.044* per occasion -- TI drifts up across the workday net of everything.
- Meetings (between): count +.287***, time -.0064***/min, opposite signs because they are
  mutually partialled (fragmentation vs. duration; see METHOD_NOTES, M5 interpretation).
- Recruitment: snowball +.26** -- report, do not bury (METHOD_NOTES has full guidance).
- Fit panel: R²m climbs .000 -> .046 (M3) -> .496 (M4) -> .572 (M5); M6 adds nothing
  (LRT p = .870).

**Manuscript use**: This is the table the Results section narrates around. Hypothesis
verdicts cite Table 5; this table carries the full coefficient evidence and the
model-building arc in one place.

**Caveats**: Variance components are point estimates (no CIs profiled). The β column for
factor-variable rows (recruitment, tenure) is not meaningful in SD units; the table leaves
those cells em-dashed.

---

## Table 4 (Strategy 2a). Model Sequence M0-M3 (`table_04_s2a_m0m3.docx`, compact variant `table_04_s2a_m0m3_compact.docx`)

**What it shows**: Side-by-side coefficient columns for M0 (unconditional), M1 (fixed
time), M2 (+ random time slope), M3 (+ L1 predictors + recruitment source), cells as
B (SE) with stars. Em dash = predictor not in that model (structural absence, not a
non-result). Source: `mlm_02_fixed_effects`.

**The compact variant** drops predictor rows that are em-dash across all four models
(rows that only become relevant at M4+), preserving the build narrative at roughly half
the height; footnotes carry what was dropped. Full grid and compact are alternatives:
pick one for the document, the other can sit in supplementary materials.

**How to read it**: Read column-to-column to watch a coefficient enter and stabilize.
The bottom rows carry variance components and fit (AIC, LRTs) per model.

**What the data say**: The within-person story is already complete at M3: PF, EE, and
competence frustration significant with essentially the same values they keep through M6
(EE .230 at M3 vs .231 at M5). Within-person estimates are rock-stable across every later
specification -- the cleanest demonstration that CWC isolates them from everything added
at L2.

**Manuscript use**: Committee-facing completeness. If the committee prefers a leaner
Results, Strategy 1 alone suffices and this pair moves to an appendix.

---

## Table 4 (Strategy 2b). Model Sequence M4-M6 (`table_04_s2b_m4m6.docx`)

**What it shows**: Same layout for M4 (+ L1 person-means), M5 (+ L2 study variables),
M6 (+ demographics). Source: `mlm_02_fixed_effects`.

**How to read it**: This table's value is in *coefficient movement across columns*:
- pf_mean_between: .529 (M4) -> .439 (M5): chronic-PF effect partially absorbed by the L2
  attitudes entering at M5.
- cw_mean_between: -.233** (M4) -> -.130* (M5): the contrary CW finding appears the moment
  chronic burnout means enter together (M4), i.e., it is a partialled-coefficient
  phenomenon among correlated burnout facets, not an artifact of the M5 attitude block.
- recruitment_sourcesnowball: .435*** (M4) -> .260** (M5): about 40% of the raw source gap
  is explained by the intake attitudes; the rest is unexplained composition difference.
- M6 column vs M5 column: nothing moves (the visual form of the stability check).

**Manuscript use**: The attenuation patterns above are Discussion material; cite specific
column-to-column shifts rather than re-running numbers in text.

---

## Table 4b. Moderation Models M7a/M7b (`table_04b_moderation.docx`)

**What it shows**: Both moderation models under a spanner header (M7a: meeting *count*
interactions; M7b: meeting *time* interactions), B and SE subcolumns per model, interaction
rows (meeting load x burnout composite, x NF composite) directly beneath their main
effects. LRT row vs. M5-with-composites baseline. Sources: `mlm_02_fixed_effects`,
`mlm_01b_phase6_comparison`.

**How to read it**: The interaction coefficients are L1 x L1 (both moderator and predictor
person-mean centered): "is the within-person depletion-to-TI slope steeper on
higher-than-usual meeting occasions?" They are NOT cross-level interactions.

**What the data say**: Nothing moderates. All four interaction terms ns (H3a count/time:
-.072/-.002; H3b count/time: .000/.003); model-level LRTs ns (M7a p = .565, M7b p = .380).
The composites note matters: burnout_mean averages in the non-significant CW, so a real
EE-specific interaction could be diluted (METHOD_NOTES flag; proposal pre-specified
composites, so this is faithful, just facet-blind).

**Manuscript use**: Report compactly as exploratory tests that did not support H3, with
the rho_beta slope-heterogeneity framing (Table 5 note + METHOD_NOTES) as the
forward-looking interpretation: slopes do vary by person (PF rho_beta = .053); meeting
load is just not what explains the variation, at least at this sample's light meeting
exposure (M = 0.72 meetings per window).

---

## Table 5. Hypothesis Test Summary (`table_05_hypothesis_tests.docx`)

**What it shows**: One row per hypothesis test, grouped under block subheadings: Need
Frustration (H1), Burnout (H2), Meeting Load Moderation (H3), Psychological Contract and
Job Satisfaction (H4, H5). Columns: Hypothesis, Description (predictor -> TI with
direction), Model (where tested), B, β, pseudo-*d*, *p*, Supported (Yes/No). Sources:
`mlm_04_hypothesis_tests`, `mlm_05_standardized_effects`, `mlm_06_level_specific_es`.

**How to read it**:
- The **Model column** matters: each hypothesis is tested at its point of entry in the
  sequence (H1a/H2a in M3; H1b/H2b in M4; H4/H5 in M5; H3 in M7a/M7b), per the proposal's
  sequential strategy. The B here can differ slightly from the M5 value in Table 4
  (e.g., H2a:ee B = .222 at M3 vs .231 at M5); both are correct, they answer different
  conditioning questions.
- **pseudo-*d*** (Lorah, 2018) is the level-specific standardized mean difference; it is
  supplementary to β and needs its definitional note (already in the table note).
- "Supported" requires *p* < .05 AND the hypothesized direction.

**What the data say** (the verdict pattern):
- Seven tests supported: H1a:comp, H2a:pf, H2a:ee, H2b:pf, H2b:ee, H4a
  (threshold: p = .050, power ~.62 -- report as provisional), H5.
- Not supported, null: H1a:auto/relt, H1b (all facets), H2a:cw, H3 (all four), H4b.
- Not supported, *contrary*: H2b:cw (-.233, p = .001) -- significant wrong-direction;
  needs its own Discussion paragraph (METHOD_NOTES has three candidate explanations).
- The pattern is facet-differentiated, not monolithic: depletion-flavored facets (PF, EE)
  and competence frustration carry the model at both levels; appraisal-flavored facets
  (autonomy, relatedness) and CW do not. That is a more precise result than "burnout
  predicts turnover" and should be sold as such.

**Manuscript use**: This is the Results closer and the Discussion outline in table form.
Walk the blocks in order; the block subheadings are the paragraph structure.

**Caveats**: 17 tests at α = .05 without family correction: the note says stars are
unadjusted. H4a at exactly p = .050 with ~.62 power must keep its provisional framing
everywhere it is mentioned.

---

## Appendix A. Full CFA Loadings (`appendix_a_cfa_loadings_full.docx`)

**What it shows**: Every item, both levels: item code, λ, SE, *p*, long format. The
complete psychometric record behind Table 3 Panel B. Source: `cfa_02`/`cfa_03`.

**How to use it**: Committee reference; cite from Table 3 in text. Item *wording* is not
in any pipeline CSV: the manuscript appendix must merge wording from the survey instrument
manually (flagged during table build; do not forget).

---

## Appendix B. Measurement Checks (`appendix_b_measurement_checks.docx`)

**What it shows**: Two panels. (1) Metric invariance: configural vs. metric SB-Δχ²(22) =
-2.35, *p* = 1.00 -- equal loadings across levels supported; the negative Δχ² is a
documented scaling-correction artifact (reporting language ready in METHOD_NOTES).
(2) CMV marker: Baseline / Method-U / Method-R LRT ladder; Method-U significant (68.69,
*p* < .001), Method-R null (2.00, *p* = 1.00). Sources: `cfa_05`-`cfa_08`.

**How to read it**: Method-R is the verdict row: marker cross-loadings exist (Method-U)
but do not bias substantive factor correlations (Method-R). The absence of Method-R
significance is the criterion, not Method-U.

**Manuscript use**: Two sentences in the main text (invariance supported; CMV does not
distort substantive relationships), table in appendix. Both are prerequisites the MLM
quietly relies on: invariance licenses same-items-both-levels; the marker result protects
the within-person correlations feeding every L1 claim.

---

## Appendix D. Full M6 Covariate Results (`appendix_d_m6_covariates.docx`)

**What it shows**: The complete M6 fixed-effects table including every demographic row the
main tables summarize (age, three job-tenure dummies). Source: `mlm_02_fixed_effects`.

**What the data say**: age B = .002 (*p* = .54); tenure dummies all ns (-.069 to +.043);
recruitment source remains significant (+.255**) with demographics present. The table is
the receipts for the claim "results are robust to demographic covariates."

**Manuscript use**: Cite once from the Results sensitivity sentence. If a committee member
asks about any specific demographic, the answer is a row in this table.

---

## Cross-table consistency rules (for drafting)

1. **N statement**: every table note reads N = 336 participants, n = 1,008 observations
   (L1 tables) or N = 336 (L2-only tables). Any other N is an error.
2. **Estimand language**: "within-person" always means CWC/rmcorr quantities;
   "between-person" always means person-mean/intake quantities. Never "controlling for
   nesting" (vague) -- name the estimator.
3. **Model attribution**: when text quotes a coefficient, it must name the model column it
   came from (M3 vs M5 values differ legitimately; see Table 5 reading note).
4. **Em dash semantics**: in every table, em dash = structurally absent (not in model,
   single item, undefined), never "not significant."
5. **Star semantics**: unadjusted p-values throughout; each table's note says so once.
