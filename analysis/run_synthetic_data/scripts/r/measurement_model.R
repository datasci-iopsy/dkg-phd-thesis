library(lavaan)
library(semTools)

options(tibble.width = Inf)
here::here()

# =============================================================================
# 1. Load fact table exported from BigQuery via scripts/syn_export_for_r.sh
# =============================================================================
df_raw <- readr::read_csv(
    here::here(
        "analysis", "run_synthetic_data", "data", "export",
        "syn_qualtrics_fct_panel_responses_20260227.csv"
    ),
    show_col_types = FALSE
)

# =============================================================================
# 2. Prepare item-level data frames
# =============================================================================

# L2 items: one row per participant (time-invariant, measured once at intake)
df_l2_items <- df_raw |>
    dplyr::distinct(response_id, .keep_all = TRUE) |>
    dplyr::select(
        id = response_id,
        pa1, pa2, pa3, pa4, pa5, # Positive Affect (I-PANAS-SF)
        na1, na2, na3, na4, na5, # Negative Affect (I-PANAS-SF)
        br1, br2, br3, br4, br5, # Psych. Contract Breach (Robinson & Morrison)
        vio1, vio2, vio3, vio4 # Psych. Contract Violation (Robinson & Morrison)
    )

# L1 items: all rows (time-varying, measured at each timepoint)
df_l1_items <- df_raw |>
    dplyr::select(
        id = response_id,
        timepoint,
        pf1, pf2, pf3, pf4, pf5, pf6, # Physical Fatigue (SMBM)
        cw1, cw2, cw3, cw4, cw5, # Cognitive Weariness (SMBM)
        ee1, ee2, ee3, # Emotional Exhaustion (SMBM)
        comp1, comp2, comp3, comp4, # Need Frustration - Competence (PNTS)
        auto1, auto2, auto3, auto4, # Need Frustration - Autonomy (PNTS)
        relt1, relt2, relt3, relt4, # Need Frustration - Relatedness (PNTS)
        atcb2, atcb5, atcb6, atcb7, # Attitude Toward Color Blue (marker)
        turnover_intention # Turnover Intention (single item)
    )

# =============================================================================
# 3. L2 single-level CFA + McDonald's omega
# -----------------------------------------------------------------------------
# L2-only scales are measured once per participant. A standard (non-multilevel)
# CFA is appropriate here because there is no within-person variance to
# decompose. Single-item Job Satisfaction (js1) is excluded — omega requires
# at least 3 indicators to identify a latent factor.
# =============================================================================
l2_cfa_model <- "
    POS_AFF =~ pa1 + pa2 + pa3 + pa4 + pa5
    NEG_AFF =~ na1 + na2 + na3 + na4 + na5
    PCB     =~ br1 + br2 + br3 + br4 + br5
    PCV     =~ vio1 + vio2 + vio3 + vio4
"

l2_cfa_fit <- lavaan::cfa(
    model     = l2_cfa_model,
    data      = df_l2_items,
    estimator = "MLR"
)
warnings()

cat("\n=== L2 CFA: Model Fit ===\n")
summary(l2_cfa_fit, fit.measures = TRUE, standardized = TRUE)

# McDonald's omega for L2 scales (single-level)
l2_omega <- semTools::compRelSEM(
    object = l2_cfa_fit,
    tau.eq = FALSE
)
cat("\n=== L2 Scales: McDonald's Omega ===\n")
print(l2_omega)

# =============================================================================
# 4. L1 multilevel CFA (MCFA) + McDonald's omega
# -----------------------------------------------------------------------------
# L1 scales are measured at each timepoint (within-person). A multilevel CFA
# decomposes total variance into within-person (Level 1) and between-person
# (Level 2) components, enabling level-specific omega estimates.
#
# Approach follows Lai (2021):
#   - omega_within: reliability of within-person fluctuation scores
#   - omega_between: reliability of person-mean scores
#
# Single-item Turnover Intention is excluded — cannot define a latent factor.
#
# References:
#   Lai (2021): https://doi.org/10.1037/met0000287
#   Blog: https://quantscience.rbind.io/posts/2022-11-13-multilevel-composite-reliability/
#   semTools: https://github.com/marklhc/mcfa_reliability_supp/blob/master/compare_semTools.md
# =============================================================================
mcfa_l1_model <- "
level: 1
    PF      =~ pf1 + pf2 + pf3 + pf4 + pf5 + pf6
    CW      =~ cw1 + cw2 + cw3 + cw4 + cw5
    EE      =~ ee1 + ee2 + ee3
    NF_COMP =~ comp1 + comp2 + comp3 + comp4
    NF_AUTO =~ auto1 + auto2 + auto3 + auto4
    NF_REL  =~ relt1 + relt2 + relt3 + relt4
    ATCB    =~ atcb2 + atcb5 + atcb6 + atcb7

level: 2
    PF      =~ pf1 + pf2 + pf3 + pf4 + pf5 + pf6
    CW      =~ cw1 + cw2 + cw3 + cw4 + cw5
    EE      =~ ee1 + ee2 + ee3
    NF_COMP =~ comp1 + comp2 + comp3 + comp4
    NF_AUTO =~ auto1 + auto2 + auto3 + auto4
    NF_REL  =~ relt1 + relt2 + relt3 + relt4
    ATCB    =~ atcb2 + atcb5 + atcb6 + atcb7
"

mcfa_l1_fit <- lavaan::cfa(
    model        = mcfa_l1_model,
    data         = df_l1_items,
    cluster      = "id",
    estimator    = "MLR",
    optim.method = "nlminb"
)
warnings()

cat("\n=== L1 MCFA: Model Fit ===\n")
summary(mcfa_l1_fit, fit.measures = TRUE, standardized = TRUE)

# McDonald's omega for L1 scales (multilevel: within + between)
l1_factors <- c("PF", "CW", "EE", "NF_COMP", "NF_AUTO", "NF_REL", "ATCB")

mcfa_l1_omega <- semTools::compRelSEM(
    object = mcfa_l1_fit,
    tau.eq = FALSE,
    config = l1_factors,
    shared = l1_factors
)
cat("\n=== L1 Scales: McDonald's Omega (Within + Between) ===\n")
print(mcfa_l1_omega)

# =============================================================================
# 5. Summary
# =============================================================================
cat("\n=== Single-Item Measures (Omega Not Estimable) ===\n")
cat("  - Job Satisfaction (js1): 1 item — L2 only\n")
cat("  - Turnover Intention (turnover_intention): 1 item — L1\n")
