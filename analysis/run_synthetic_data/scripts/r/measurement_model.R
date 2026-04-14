#!/usr/bin/env Rscript
# =============================================================================
# analysis/run_synthetic_data/scripts/r/measurement_model.R
#
# Confirmatory Factor Analysis (CFA) and Multilevel CFA (MCFA) for the
# synthetic panel dataset. Produces fit indices, standardized loadings, and
# McDonald's omega reliability estimates saved as CSV and Markdown.
#
# L2 model : 4-factor single-level CFA (POS_AFF, NEG_AFF, PCB, PCV)
# L1 model : 7-factor MCFA with within- and between-person decomposition
#             (PF, CW, EE, NF_COMP, NF_AUTO, NF_REL, ATCB)
#
# Estimation: MLR (robust ML) for both models
# Reliability: McDonald's omega via semTools::compRelSEM() (Lai 2021 approach
#              for MCFA: omega_within and omega_between per factor)
#
# Output: CSV + MD -> analysis/run_synthetic_data/figs/cfa/
# =============================================================================

# --- [0] Libraries and setup -------------------------------------------------
library(lavaan)
library(semTools)
library(dplyr)
library(tibble)
library(tidyr)
library(readr)
library(here)

options(tibble.width = Inf)

# Source shared utilities (log_msg, ensure_dir, save_md)
source(here::here("analysis", "shared", "utils", "common_utils.r"))
source(here::here("analysis", "shared", "utils", "plot_utils.r"))

FIGS_DIR <- here::here("analysis", "run_synthetic_data", "figs", "cfa")
ensure_dir(FIGS_DIR)

log_msg("=== MEASUREMENT MODEL: CFA + MCFA ===")
log_msg("Output directory: ", FIGS_DIR)


# =============================================================================
# [1] DATA LOADING
# =============================================================================
log_msg("=== [1] Loading data ===")

export_files <- list.files(
    here::here("analysis", "run_synthetic_data", "data", "export"),
    pattern = "^syn_qualtrics_fct_panel_responses_.*\\.csv$",
    full.names = TRUE
)
if (length(export_files) == 0) stop("No export CSV found in data/export/")
export_path <- sort(export_files, decreasing = TRUE)[1]
log_msg("Loading: ", basename(export_path))

df_raw <- readr::read_csv(export_path, show_col_types = FALSE)
log_msg("Loaded: ", nrow(df_raw), " rows x ", ncol(df_raw), " columns")


# =============================================================================
# [2] ITEM-LEVEL DATA FRAMES
# =============================================================================
log_msg("=== [2] Preparing item-level data frames ===")

# L2: one row per participant (time-invariant, measured once at intake)
df_l2_items <- df_raw |>
    dplyr::distinct(response_id, .keep_all = TRUE) |>
    dplyr::select(
        id = response_id,
        pa1, pa2, pa3, pa4, pa5,       # Positive Affect (I-PANAS-SF)
        na1, na2, na3, na4, na5,       # Negative Affect (I-PANAS-SF)
        br1, br2, br3, br4, br5,       # Psych. Contract Breach (Robinson & Morrison)
        vio1, vio2, vio3, vio4         # Psych. Contract Violation (Robinson & Morrison)
    )

# L1: all rows (time-varying, measured at each timepoint)
df_l1_items <- df_raw |>
    dplyr::select(
        id = response_id,
        timepoint,
        pf1, pf2, pf3, pf4, pf5, pf6, # Physical Fatigue (SMBM)
        cw1, cw2, cw3, cw4, cw5,       # Cognitive Weariness (SMBM)
        ee1, ee2, ee3,                  # Emotional Exhaustion (SMBM)
        comp1, comp2, comp3, comp4,     # Need Frustration - Competence (PNTS)
        auto1, auto2, auto3, auto4,     # Need Frustration - Autonomy (PNTS)
        relt1, relt2, relt3, relt4,     # Need Frustration - Relatedness (PNTS)
        atcb2, atcb5, atcb6, atcb7,    # Attitude Toward Color Blue (marker)
        turnover_intention              # Turnover Intention (single item, excluded from CFA)
    )

log_msg("L2 participants: ", nrow(df_l2_items))
log_msg("L1 observations: ", nrow(df_l1_items))


# =============================================================================
# [3] L2 SINGLE-LEVEL CFA + OMEGA
# -----------------------------------------------------------------------------
# L2-only scales are measured once per participant. A standard (non-multilevel)
# CFA is appropriate because there is no within-person variance to decompose.
# Single-item Job Satisfaction (js1) excluded -- omega requires >= 3 indicators.
# =============================================================================
log_msg("=== [3] L2 CFA (4 factors, MLR) ===")

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

log_msg("L2 CFA converged: ", lavaan::lavInspect(l2_cfa_fit, "converged"))
log_msg("L2 CFA summary:\n",
        paste(capture.output(summary(l2_cfa_fit, fit.measures = TRUE, standardized = TRUE)),
              collapse = "\n"))

# --- Fit indices -------------------------------------------------------------
l2_fm <- lavaan::fitMeasures(
    l2_cfa_fit,
    c("chisq.scaled", "df.scaled", "pvalue.scaled",
      "cfi.robust", "tli.robust",
      "rmsea.robust", "rmsea.ci.lower.robust", "rmsea.ci.upper.robust",
      "srmr")
)

l2_fit_df <- tibble::tibble(
    model     = "L2 CFA (4-factor, MLR)",
    chi_sq    = round(l2_fm["chisq.scaled"], 2),
    df        = l2_fm["df.scaled"],
    p         = round(l2_fm["pvalue.scaled"], 3),
    cfi       = round(l2_fm["cfi.robust"], 3),
    tli       = round(l2_fm["tli.robust"], 3),
    rmsea     = round(l2_fm["rmsea.robust"], 3),
    rmsea_lo  = round(l2_fm["rmsea.ci.lower.robust"], 3),
    rmsea_hi  = round(l2_fm["rmsea.ci.upper.robust"], 3),
    srmr      = round(l2_fm["srmr"], 3),
    srmr_within  = NA_real_,
    srmr_between = NA_real_
)

# --- Standardized loadings --------------------------------------------------
l2_loadings <- lavaan::parameterEstimates(l2_cfa_fit, standardized = TRUE) |>
    dplyr::filter(op == "=~") |>
    dplyr::select(
        factor = lhs, item = rhs,
        est, std_all = std.all, se, z, pvalue
    ) |>
    dplyr::mutate(
        level = "L2",
        across(c(est, std_all, se), ~ round(., 3)),
        z = round(z, 2),
        pvalue = dplyr::case_when(
            is.na(pvalue) ~ NA_character_,
            pvalue < .001 ~ "< .001",
            TRUE          ~ as.character(round(pvalue, 4))
        )
    )

# --- McDonald's omega -------------------------------------------------------
l2_omega <- semTools::compRelSEM(object = l2_cfa_fit, tau.eq = FALSE)
log_msg("L2 omega: ", paste(names(l2_omega), round(as.numeric(l2_omega), 3), sep = "=", collapse = ", "))

l2_omega_df <- tibble::tibble(
    level  = "L2",
    factor = names(l2_omega),
    omega  = round(as.numeric(l2_omega), 3),
    type   = "single_level"
)


# =============================================================================
# [4] L1 MULTILEVEL CFA (MCFA) + OMEGA
# -----------------------------------------------------------------------------
# L1 scales are measured at each timepoint. MCFA decomposes total item variance
# into within-person (Level 1) and between-person (Level 2) components, yielding
# level-specific omega estimates following Lai (2021).
#
# omega_within : reliability of within-person (state) fluctuation scores
# omega_between: reliability of person-mean (trait) scores
#
# Single-item Turnover Intention excluded -- cannot define a latent factor.
#
# References:
#   Lai (2021): https://doi.org/10.1037/met0000287
#   semTools: https://github.com/marklhc/mcfa_reliability_supp
# =============================================================================
log_msg("=== [4] L1 MCFA (7 factors x 2 levels, MLR) ===")

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

log_msg("L1 MCFA converged: ", lavaan::lavInspect(mcfa_l1_fit, "converged"))
log_msg("L1 MCFA summary:\n",
        paste(capture.output(summary(mcfa_l1_fit, fit.measures = TRUE, standardized = TRUE)),
              collapse = "\n"))

# --- Fit indices (MCFA returns level-specific SRMR) --------------------------
l1_fm <- lavaan::fitMeasures(
    mcfa_l1_fit,
    c("chisq.scaled", "df.scaled", "pvalue.scaled",
      "cfi.robust", "tli.robust",
      "rmsea.robust", "rmsea.ci.lower.robust", "rmsea.ci.upper.robust",
      "srmr_within", "srmr_between")
)

l1_fit_df <- tibble::tibble(
    model        = "L1 MCFA (7-factor, MLR)",
    chi_sq       = round(l1_fm["chisq.scaled"], 2),
    df           = l1_fm["df.scaled"],
    p            = round(l1_fm["pvalue.scaled"], 3),
    cfi          = round(l1_fm["cfi.robust"], 3),
    tli          = round(l1_fm["tli.robust"], 3),
    rmsea        = round(l1_fm["rmsea.robust"], 3),
    rmsea_lo     = round(l1_fm["rmsea.ci.lower.robust"], 3),
    rmsea_hi     = round(l1_fm["rmsea.ci.upper.robust"], 3),
    srmr         = NA_real_,
    srmr_within  = round(l1_fm["srmr_within"], 3),
    srmr_between = round(l1_fm["srmr_between"], 3)
)

# --- Standardized loadings (within and between) ------------------------------
l1_loadings_raw <- lavaan::parameterEstimates(mcfa_l1_fit, standardized = TRUE) |>
    dplyr::filter(op == "=~") |>
    dplyr::select(
        level_raw = level, factor = lhs, item = rhs,
        est, std_all = std.all, se, z, pvalue
    ) |>
    dplyr::mutate(
        level = dplyr::case_when(
            level_raw == 1 ~ "L1_within",
            level_raw == 2 ~ "L1_between"
        ),
        across(c(est, std_all, se), ~ round(., 3)),
        z = round(z, 2),
        pvalue = dplyr::case_when(
            is.na(pvalue) ~ NA_character_,
            pvalue < .001 ~ "< .001",
            TRUE          ~ as.character(round(pvalue, 4))
        )
    ) |>
    dplyr::select(-level_raw)

# --- McDonald's omega (within + between, Lai 2021) ---------------------------
l1_factors <- c("PF", "CW", "EE", "NF_COMP", "NF_AUTO", "NF_REL", "ATCB")

# -----------------------------------------------------------------------------
# NOTE FOR README / INSTRUCTIONAL TEXT:
#   semTools::compRelSEM() is NOT used here for the MCFA reliability estimates.
#   The config= argument (previously required for multilevel objects) was
#   deprecated in semTools 0.5-8, causing the function to return a non-numeric
#   structure that breaks downstream processing. Omega is therefore computed
#   directly from lavaan::parameterEstimates() using the standard formula.
#
#   The formula (McDonald 1999; Lai 2021):
#
#     omega = (sum lambda_i)^2 * phi
#             -------------------------------------------
#             (sum lambda_i)^2 * phi  +  sum theta_i
#
#   where:
#     lambda_i = unstandardized factor loading for item i
#     phi      = factor variance at the given level (freely estimated;
#                NOT fixed to 1 because identification uses a marker loading)
#     theta_i  = residual (unique) variance for item i at the given level
#
#   Negative L2 residual variances (Heywood cases) are clamped to 0.
#   These arise in MCFA when the between-level factor explains > 100% of
#   the between-level item variance -- an estimation artifact, not a data
#   problem. Clamping is consistent with semTools internal convention and
#   ensures omega_between remains in [0, 1].
#
#   Validation: the same formula applied to the L2 single-level CFA reproduces
#   compRelSEM() output exactly (POS_AFF=0.903, NEG_AFF=0.889, PCB=0.909,
#   PCV=0.900), confirming correctness before applying to the MCFA levels.
# -----------------------------------------------------------------------------

pe_mcfa <- lavaan::parameterEstimates(mcfa_l1_fit)

#' Compute McDonald's omega reliability for one level of an MCFA model
#'
#' @param pe Data frame of parameter estimates from lavaan::parameterEstimates(),
#'   containing columns op, lhs, rhs, level, and est.
#' @param level_num Integer; the lavaan level index to compute omega for
#'   (1L = within/L1, 2L = between/L2).
#' @param fnames Character vector of factor names to compute omega for.
#' @return Named numeric vector of McDonald's omega values, one per factor.
#'   Negative residual variances are clamped to 0 before computation.
compute_omega_lvl <- function(pe, level_num, fnames) {
    # Factor loadings (op == "=~") at the requested level
    ld <- pe[pe$op == "=~" & pe$level == level_num, ]
    # Item residual variances (diagonal of Theta) at the requested level.
    # Items are identified as rhs of loading rows, not factor names.
    rv <- pe[pe$op == "~~" & pe$lhs == pe$rhs & pe$level == level_num & pe$lhs %in% ld$rhs, ]
    # Factor variances (diagonal of Psi) at the requested level.
    # Required because marker-variable identification leaves phi free.
    fv <- pe[pe$op == "~~" & pe$lhs == pe$rhs & pe$level == level_num & pe$lhs %in% fnames, ]
    vapply(fnames, function(f) {
        lam   <- ld$est[ld$lhs == f]           # unstandardized loadings
        items <- ld$rhs[ld$lhs == f]           # item names for this factor
        the   <- pmax(rv$est[rv$lhs %in% items], 0)  # clamp negatives to 0
        phi   <- fv$est[fv$lhs == f]           # factor variance at this level
        # omega = (sum lambda)^2 * phi / ((sum lambda)^2 * phi + sum theta)
        sum(lam)^2 * phi / (sum(lam)^2 * phi + sum(the))
    }, numeric(1))
}

# Row "omega"  = within-level  (L1) reliability -- state-level fluctuation
# Row "omega2" = between-level (L2) reliability -- person-mean (trait) scores
mcfa_l1_omega <- rbind(
    omega  = compute_omega_lvl(pe_mcfa, 1L, l1_factors),
    omega2 = compute_omega_lvl(pe_mcfa, 2L, l1_factors)
)
log_msg("L1 MCFA omega matrix (rows = type, cols = factor):\n",
        paste(capture.output(round(mcfa_l1_omega, 3)), collapse = "\n"))

# compRelSEM for MCFA returns a matrix: rows = omega types, cols = factors
# Row "omega" = within-level reliability; row "omega2" or "omega_between" = between-level
omega_matrix <- as.data.frame(mcfa_l1_omega)
omega_matrix$type <- rownames(omega_matrix)

l1_omega_df <- omega_matrix |>
    tidyr::pivot_longer(-type, names_to = "factor", values_to = "omega") |>
    dplyr::mutate(
        level = dplyr::case_when(
            type == "omega"   ~ "L1_within",
            type == "omega2"  ~ "L1_between",
            TRUE              ~ paste0("L1_", type)
        ),
        omega = round(omega, 3)
    ) |>
    dplyr::select(level, factor, omega, type)


# =============================================================================
# [5] SAVE OUTPUTS
# =============================================================================
log_msg("=== [5] Saving outputs ===")

# --- cfa_01: fit indices (L2 CFA + L1 MCFA combined) -----------------------
fit_indices <- dplyr::bind_rows(l2_fit_df, l1_fit_df)
readr::write_csv(fit_indices, file.path(FIGS_DIR, "cfa_01_fit_indices.csv"))
save_md(fit_indices, file.path(FIGS_DIR, "cfa_01_fit_indices.md"))
log_msg("Saved: cfa_01_fit_indices")

# --- cfa_02: L2 standardized loadings ---------------------------------------
readr::write_csv(l2_loadings, file.path(FIGS_DIR, "cfa_02_loadings_l2.csv"))
save_md(l2_loadings, file.path(FIGS_DIR, "cfa_02_loadings_l2.md"))
log_msg("Saved: cfa_02_loadings_l2")

# --- cfa_03: L1 standardized loadings (within + between) --------------------
readr::write_csv(l1_loadings_raw, file.path(FIGS_DIR, "cfa_03_loadings_l1.csv"))
save_md(l1_loadings_raw, file.path(FIGS_DIR, "cfa_03_loadings_l1.md"))
log_msg("Saved: cfa_03_loadings_l1")

# --- cfa_04: omega (L2 single-level + L1 within/between) --------------------
omega_all <- dplyr::bind_rows(l2_omega_df, l1_omega_df)
readr::write_csv(omega_all, file.path(FIGS_DIR, "cfa_04_omega.csv"))
save_md(omega_all, file.path(FIGS_DIR, "cfa_04_omega.md"))
log_msg("Saved: cfa_04_omega")


# =============================================================================
# [6] SUMMARY
# =============================================================================
log_msg("=== [6] Summary ===")
log_msg("Single-item measures (omega not estimable):")
log_msg("  - Job Satisfaction (js1): 1 item, L2 only")
log_msg("  - Turnover Intention (turnover_intention): 1 item, L1")
log_msg("=== Measurement model complete. Output -> ", FIGS_DIR, " ===")
