#!/usr/bin/env Rscript
# =============================================================================
# analysis/run_study_analysis/scripts/R/measurement_model.r
#
# CFA and Multilevel CFA (MCFA) for the real participant panel dataset.
# Produces fit indices, standardized loadings, and McDonald's omega saved
# as CSV and Markdown.
#
# L2 model : 4-factor single-level CFA (POS_AFF, NEG_AFF, PCB, PCV)
# L1 model : 7-factor MCFA with within- and between-person decomposition
#             (PF, CW, EE, NF_COMP, NF_AUTO, NF_REL, ATCB)
#
# PF factor uses 5 items (pf1, pf2, pf4, pf5, pf6). pf3 is excluded at
# all timepoints because it was absent from the 1PM and 5PM surveys
# (survey design omission; see METHOD_NOTES.md). Using pf3 only at tp1
# would violate measurement equivalence across timepoints.
#
# Estimation: MLR (robust ML) for both models
# Reliability: McDonald's omega (Lai 2021 approach for MCFA)
#
# Output: CSV + MD -> analysis/run_study_analysis/figs/cfa/
# =============================================================================

# --- [0] Libraries and setup -------------------------------------------------
library(lavaan)
library(semTools)
library(rmcorr)
library(dplyr)
library(tibble)
library(tidyr)
library(readr)
library(here)

options(tibble.width = Inf)

source(here::here("analysis", "shared", "utils", "common_utils.r"))
source(here::here("analysis", "shared", "utils", "plot_utils.r"))
source(here::here("analysis", "run_study_analysis", "utils", "data_loader.r"))
source(here::here("analysis", "run_study_analysis", "utils", "prep_levels.r"))

FIGS_DIR <- here::here("analysis", "run_study_analysis", "figs", "cfa")
ensure_dir(FIGS_DIR)

log_msg("=== MEASUREMENT MODEL: CFA + MCFA ===")
log_msg("Output directory: ", FIGS_DIR)


# =============================================================================
# [1] DATA LOADING AND PARTITIONING
# =============================================================================
log_msg("=== [1] Loading data ===")

df_raw <- load_cleaned_data()
levels <- partition_levels(df_raw)


# =============================================================================
# [2] ITEM-LEVEL DATA FRAMES
# =============================================================================
log_msg("=== [2] Preparing item-level data frames ===")

# L2: one row per participant; raw items come from df_raw (levels$l2 has means only)
df_l2_items <- df_raw |>
    dplyr::distinct(response_id, .keep_all = TRUE) |>
    dplyr::select(
        id = response_id,
        pa1, pa2, pa3, pa4, pa5,
        na1, na2, na3, na4, na5,
        br1, br2, br3, br4, br5,
        vio1, vio2, vio3, vio4,
        des1, des2
    )

# L1: all rows (time-varying, measured at each timepoint)
# pf3 excluded: absent from 1PM/5PM surveys (survey design omission).
df_l1_items <- df_raw |>
    dplyr::select(
        id = response_id,
        timepoint,
        pf1, pf2, pf4, pf5, pf6,
        cw1, cw2, cw3, cw4, cw5,
        ee1, ee2, ee3,
        comp1, comp2, comp3, comp4,
        auto1, auto2, auto3, auto4,
        relt1, relt2, relt3, relt4,
        atcb2, atcb5, atcb6, atcb7,
        turnover_intention
    )

log_msg("L2 participants: ", nrow(df_l2_items))
log_msg("L1 observations: ", nrow(df_l1_items))


# =============================================================================
# [3] L2 SINGLE-LEVEL CFA + OMEGA
# =============================================================================
log_msg("=== [3] L2 CFA (4 factors, MLR) ===")

l2_cfa_model <- "
    POS_AFF =~ pa1 + pa2 + pa3 + pa4 + pa5
    NEG_AFF =~ na1 + na2 + na3 + na4 + na5
    PCB     =~ br1 + br2 + br3 + br4 + br5
    PCV     =~ vio1 + vio2 + vio3 + vio4
    DES     =~ des1 + des2
"

l2_cfa_fit <- lavaan::cfa(
    model     = l2_cfa_model,
    data      = df_l2_items,
    estimator = "MLR"
)

log_msg("L2 CFA converged: ", lavaan::lavInspect(l2_cfa_fit, "converged"))
log_msg(
    "L2 CFA summary:\n",
    paste(capture.output(summary(l2_cfa_fit, fit.measures = TRUE, standardized = TRUE)),
        collapse = "\n"
    )
)

# --- Fit indices -------------------------------------------------------------
l2_fm <- lavaan::fitMeasures(
    l2_cfa_fit,
    c(
        "chisq.scaled", "df.scaled", "pvalue.scaled",
        "cfi.robust", "tli.robust",
        "rmsea.robust", "rmsea.ci.lower.robust", "rmsea.ci.upper.robust",
        "srmr"
    )
)

l2_fit_df <- tibble::tibble(
    model        = "L2 CFA (4-factor, MLR)",
    chi_sq       = round(l2_fm["chisq.scaled"], 2),
    df           = l2_fm["df.scaled"],
    p            = round(l2_fm["pvalue.scaled"], 3),
    cfi          = round(l2_fm["cfi.robust"], 3),
    tli          = round(l2_fm["tli.robust"], 3),
    rmsea        = round(l2_fm["rmsea.robust"], 3),
    rmsea_lo     = round(l2_fm["rmsea.ci.lower.robust"], 3),
    rmsea_hi     = round(l2_fm["rmsea.ci.upper.robust"], 3),
    srmr         = round(l2_fm["srmr"], 3),
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
            TRUE ~ as.character(round(pvalue, 4))
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
# PF modeled with 5 items (pf1, pf2, pf4, pf5, pf6). pf3 excluded at
# all timepoints for measurement equivalence (absent at tp2/tp3 by survey
# design; see METHOD_NOTES.md).
#
# omega_within : reliability of within-person (state) fluctuation scores
# omega_between: reliability of person-mean (trait) scores
#
# Omega computed directly from parameterEstimates() rather than
# semTools::compRelSEM(). See NOTE in synthetic measurement_model.r
# for rationale (semTools 0.5-8 config= deprecation).
# =============================================================================
log_msg("=== [4] L1 MCFA (7 factors x 2 levels, MLR) ===")

mcfa_l1_model <- "
level: 1
    PF      =~ pf1 + pf2 + pf4 + pf5 + pf6
    CW      =~ cw1 + cw2 + cw3 + cw4 + cw5
    EE      =~ ee1 + ee2 + ee3
    NF_COMP =~ comp1 + comp2 + comp3 + comp4
    NF_AUTO =~ auto1 + auto2 + auto3 + auto4
    NF_REL  =~ relt1 + relt2 + relt3 + relt4
    ATCB    =~ atcb2 + atcb5 + atcb6 + atcb7

level: 2
    PF      =~ pf1 + pf2 + pf4 + pf5 + pf6
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
log_msg(
    "L1 MCFA summary:\n",
    paste(capture.output(summary(mcfa_l1_fit, fit.measures = TRUE, standardized = TRUE)),
        collapse = "\n"
    )
)

# --- Fit indices -------------------------------------------------------------
l1_fm <- lavaan::fitMeasures(
    mcfa_l1_fit,
    c(
        "chisq.scaled", "df.scaled", "pvalue.scaled",
        "cfi.robust", "tli.robust",
        "rmsea.robust", "rmsea.ci.lower.robust", "rmsea.ci.upper.robust",
        "srmr_within", "srmr_between"
    )
)

l1_fit_df <- tibble::tibble(
    model        = "L1 MCFA (7-factor, 5-item PF, MLR)",
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
            TRUE ~ as.character(round(pvalue, 4))
        )
    ) |>
    dplyr::select(-level_raw)

# --- McDonald's omega (within + between, Lai 2021) ---------------------------
l1_factors <- c("PF", "CW", "EE", "NF_COMP", "NF_AUTO", "NF_REL", "ATCB")

pe_mcfa <- lavaan::parameterEstimates(mcfa_l1_fit)

#' Compute McDonald's omega for one level of an MCFA model
#'
#' @param pe Data frame from lavaan::parameterEstimates() with columns
#'   op, lhs, rhs, level, and est.
#' @param level_num Integer; 1L = within, 2L = between.
#' @param fnames Character vector of factor names.
#' @return Named numeric vector of omega values, one per factor.
#'   Negative residual variances clamped to 0 (Heywood case handling).
compute_omega_lvl <- function(pe, level_num, fnames) {
    ld <- pe[pe$op == "=~" & pe$level == level_num, ]
    rv <- pe[pe$op == "~~" & pe$lhs == pe$rhs & pe$level == level_num & pe$lhs %in% ld$rhs, ]
    fv <- pe[pe$op == "~~" & pe$lhs == pe$rhs & pe$level == level_num & pe$lhs %in% fnames, ]
    vapply(fnames, function(f) {
        lam <- ld$est[ld$lhs == f]
        items <- ld$rhs[ld$lhs == f]
        the <- pmax(rv$est[rv$lhs %in% items], 0)
        phi <- fv$est[fv$lhs == f]
        sum(lam)^2 * phi / (sum(lam)^2 * phi + sum(the))
    }, numeric(1))
}

mcfa_l1_omega <- rbind(
    omega  = compute_omega_lvl(pe_mcfa, 1L, l1_factors),
    omega2 = compute_omega_lvl(pe_mcfa, 2L, l1_factors)
)
log_msg(
    "L1 MCFA omega matrix (rows = type, cols = factor):\n",
    paste(capture.output(round(mcfa_l1_omega, 3)), collapse = "\n")
)

omega_matrix <- as.data.frame(mcfa_l1_omega)
omega_matrix$type <- rownames(omega_matrix)

l1_omega_df <- omega_matrix |>
    tidyr::pivot_longer(-type, names_to = "factor", values_to = "omega") |>
    dplyr::mutate(
        level = dplyr::case_when(
            type == "omega" ~ "L1_within",
            type == "omega2" ~ "L1_between",
            TRUE ~ paste0("L1_", type)
        ),
        omega = round(omega, 3)
    ) |>
    dplyr::select(level, factor, omega, type)


# =============================================================================
# [4b] METRIC INVARIANCE TEST (configural vs. metric MCFA)
# -----------------------------------------------------------------------------
# The configural model (mcfa_l1_fit, [4]) imposes the same factor structure at
# L1 and L2 but leaves loadings free to differ across levels. Metric invariance
# constrains loadings to be equal, which is required to interpret the same
# construct as meaning the same thing at both the within-person (CWC) and
# between-person (person-mean) levels in the MLM. Test via Satorra-Bentler
# scaled chi-square difference (appropriate for MLR).
# Cite: Hox (2010); Geldhof et al. (2014); Menghini et al. (2024 ESM template)
# =============================================================================
log_msg("=== [4b] Metric invariance test ===")

factor_items_map <- list(
    PF      = c("pf1", "pf2", "pf4", "pf5", "pf6"),
    CW      = c("cw1", "cw2", "cw3", "cw4", "cw5"),
    EE      = c("ee1", "ee2", "ee3"),
    NF_COMP = c("comp1", "comp2", "comp3", "comp4"),
    NF_AUTO = c("auto1", "auto2", "auto3", "auto4"),
    NF_REL  = c("relt1", "relt2", "relt3", "relt4"),
    ATCB    = c("atcb2", "atcb5", "atcb6", "atcb7")
)

metric_factor_block <- paste(
    vapply(names(factor_items_map), function(fac) {
        items <- factor_items_map[[fac]]
        labeled <- paste0("lam_", tolower(fac), "_", items, "*", items)
        paste0("    ", fac, " =~ ", paste(labeled, collapse = " + "))
    }, character(1)),
    collapse = "\n"
)

mcfa_metric_model <- paste(
    "level: 1", metric_factor_block,
    "level: 2", metric_factor_block,
    sep = "\n"
)

mcfa_metric_fit <- tryCatch(
    lavaan::cfa(
        model        = mcfa_metric_model,
        data         = df_l1_items,
        cluster      = "id",
        estimator    = "MLR",
        optim.method = "nlminb"
    ),
    error = function(e) {
        log_msg("  Metric MCFA failed: ", conditionMessage(e))
        NULL
    }
)

metric_invariance_df <- NULL
if (!is.null(mcfa_metric_fit) && lavaan::lavInspect(mcfa_metric_fit, "converged")) {
    log_msg("  Metric MCFA converged")
    metric_lrt <- tryCatch(
        lavaan::lavTestLRT(mcfa_l1_fit, mcfa_metric_fit,
            method = "satorra.bentler.2010"
        ),
        error = function(e) {
            log_msg("  LRT failed: ", conditionMessage(e))
            NULL
        }
    )
    if (!is.null(metric_lrt)) {
        lrt_df <- as.data.frame(metric_lrt)
        delta_chi2 <- lrt_df[2, "Chisq diff"]
        delta_df <- lrt_df[2, "Df diff"]
        delta_p <- lrt_df[2, "Pr(>Chisq)"]
        log_msg(
            "  Configural vs. Metric LRT (SB): delta_chi2 = ", round(delta_chi2, 3),
            ", delta_df = ", delta_df,
            ", p = ", format.pval(delta_p, digits = 4)
        )
        metric_invariance_df <- tibble::tibble(
            model = c("Configural", "Metric"),
            chi2 = round(lrt_df$Chisq, 2),
            df = lrt_df$Df,
            delta_chi2 = c(NA_real_, round(delta_chi2, 3)),
            delta_df = c(NA_integer_, as.integer(delta_df)),
            p_diff = c(NA_real_, round(delta_p, 4)),
            result = c(
                NA_character_,
                dplyr::case_when(
                    is.na(delta_p) ~ "inconclusive",
                    delta_p >= .05 ~ "metric invariance supported",
                    TRUE ~ "metric non-invariance detected"
                )
            )
        )
    }
} else {
    log_msg("  Metric MCFA did not converge; recording as inconclusive")
    metric_invariance_df <- tibble::tibble(
        model = c("Configural", "Metric"),
        result = c(NA_character_, "metric model did not converge")
    )
}

if (!is.null(metric_invariance_df)) {
    save_md(metric_invariance_df, file.path(FIGS_DIR, "cfa_08_metric_invariance.md"))
    readr::write_csv(metric_invariance_df, file.path(FIGS_DIR, "cfa_08_metric_invariance.csv"))
    log_msg("  Saved: cfa_08_metric_invariance")
}


# =============================================================================
# [5] CFA MARKER VARIABLE TECHNIQUE
# -----------------------------------------------------------------------------
# Level 1 (within-person) only.
#
# Level 2 excluded: the L2 scales (POS_AFF, NEG_AFF, PCB, PCV) were collected
# at intake in a separate session from the daily ESM surveys. Common method
# variance from the survey context (mood state, acquiescence, demand
# characteristics) can only co-contaminate measures administered in the same
# survey occasion. L2 and L1 constructs were not collected concurrently; a
# marker variable test at L2 would address a source of variance that is absent
# by design.
#
# Abbreviated strategy (Williams et al., 2010; Williams & McGonagle, 2016):
#   Step 1 (evidence) : ATCB within-person rmcorr with all L1 substantive vars
#   Step 2 (baseline) : Existing MCFA from [4] is the Baseline model
#   Step 3 (Method-U) : Free ATCB cross-loadings on all 25 L1 substantive items;
#                       scaled chi-sq diff test (Satorra-Bentler 2010 for MLR)
#   Step 4 (Method-R) : Conditional; run only if Method-U is significant;
#                       fix L1 substantive factor covariances to Baseline values
#
# Marker: ATCB (Aversion to Change; Miller & Simmering, 2023; Miller et al., 2024)
# Items : atcb2, atcb5, atcb6, atcb7
# =============================================================================
log_msg("=== [5] CFA Marker Variable Technique (L1 only) ===")

marker_evidence_df <- NULL
marker_fit_df <- NULL
marker_lrt_df <- NULL

# --- [5a] Marker evidence: ATCB within-person rmcorr -------------------------
log_msg("  [5a] ATCB within-person rmcorr with substantive scale means")

atcb_subst_vars <- c(
    "pf_mean", "cw_mean", "ee_mean",
    "comp_mean", "auto_mean", "relt_mean",
    "turnover_intention_mean"
)

df_marker <- df_raw |>
    dplyr::select(response_id, atcb_mean, dplyr::all_of(atcb_subst_vars)) |>
    tidyr::drop_na()

rmc_atcb <- rmcorr::rmcorr_mat(
    participant = response_id,
    variables   = c("atcb_mean", atcb_subst_vars),
    dataset     = df_marker,
    CI.level    = 0.95
)
rmc_atcb$matrix[is.nan(rmc_atcb$matrix)] <- 0

atcb_r_vals <- rmc_atcb$matrix["atcb_mean", atcb_subst_vars]

marker_evidence_df <- tibble::tibble(
    variable = names(atcb_r_vals),
    rmcorr_r = round(as.numeric(atcb_r_vals), 3)
) |>
    dplyr::mutate(near_zero = abs(rmcorr_r) < 0.10)

log_msg(
    "  ATCB within-person rmcorr with substantive vars:\n",
    paste(capture.output(print(marker_evidence_df, n = Inf)), collapse = "\n")
)

# --- [5b] Baseline: mcfa_l1_fit from [4] -------------------------------------
# mcfa_l1_fit is the Baseline (Model 1); no additional fitting required

# --- [5c] Method-U: free ATCB cross-loadings on all L1 substantive items ----
log_msg("  [5c] Fitting Method-U MCFA (ATCB cross-loadings at L1, 25 items)")

l1_subst_items <- c(
    "pf1", "pf2", "pf4", "pf5", "pf6",
    "cw1", "cw2", "cw3", "cw4", "cw5",
    "ee1", "ee2", "ee3",
    "comp1", "comp2", "comp3", "comp4",
    "auto1", "auto2", "auto3", "auto4",
    "relt1", "relt2", "relt3", "relt4"
)

method_u_lines <- c(
    "level: 1",
    "    PF      =~ pf1 + pf2 + pf4 + pf5 + pf6",
    "    CW      =~ cw1 + cw2 + cw3 + cw4 + cw5",
    "    EE      =~ ee1 + ee2 + ee3",
    "    NF_COMP =~ comp1 + comp2 + comp3 + comp4",
    "    NF_AUTO =~ auto1 + auto2 + auto3 + auto4",
    "    NF_REL  =~ relt1 + relt2 + relt3 + relt4",
    "    ATCB    =~ atcb2 + atcb5 + atcb6 + atcb7",
    paste0("    ATCB    =~ ", paste(l1_subst_items, collapse = " + ")),
    "level: 2",
    "    PF      =~ pf1 + pf2 + pf4 + pf5 + pf6",
    "    CW      =~ cw1 + cw2 + cw3 + cw4 + cw5",
    "    EE      =~ ee1 + ee2 + ee3",
    "    NF_COMP =~ comp1 + comp2 + comp3 + comp4",
    "    NF_AUTO =~ auto1 + auto2 + auto3 + auto4",
    "    NF_REL  =~ relt1 + relt2 + relt3 + relt4",
    "    ATCB    =~ atcb2 + atcb5 + atcb6 + atcb7"
)
mcfa_method_u_model <- paste(method_u_lines, collapse = "\n")

mcfa_method_u_fit <- tryCatch(
    lavaan::cfa(
        model        = mcfa_method_u_model,
        data         = df_l1_items,
        cluster      = "id",
        estimator    = "MLR",
        optim.method = "nlminb"
    ),
    error = function(e) {
        log_msg("  WARNING: Method-U model error: ", conditionMessage(e))
        NULL
    }
)

method_u_result <- "not_estimated"

if (!is.null(mcfa_method_u_fit) && isTRUE(lavaan::lavInspect(mcfa_method_u_fit, "converged"))) {
    log_msg("  Method-U converged: TRUE")

    lrt_u <- lavaan::lavTestLRT(
        mcfa_l1_fit, mcfa_method_u_fit,
        method = "satorra.bentler.2010"
    )
    u_chisq <- lrt_u[2, "Chisq diff"]
    u_df <- lrt_u[2, "Df diff"]
    u_p <- lrt_u[2, "Pr(>Chisq)"]
    method_u_result <- if (!is.na(u_p) && u_p < 0.05) "significant" else "not_significant"

    log_msg(
        "  SB chi-sq diff: ", round(u_chisq, 3),
        ", df = ", u_df, ", p = ", round(u_p, 4),
        "  [", method_u_result, "]"
    )

    baseline_fm <- lavaan::fitMeasures(
        mcfa_l1_fit,
        c(
            "chisq.scaled", "df.scaled", "cfi.robust", "rmsea.robust",
            "srmr_within", "srmr_between"
        )
    )
    method_u_fm <- lavaan::fitMeasures(
        mcfa_method_u_fit,
        c(
            "chisq.scaled", "df.scaled", "cfi.robust", "rmsea.robust",
            "srmr_within", "srmr_between"
        )
    )

    marker_fit_df <- tibble::tibble(
        model = c("Baseline (MCFA)", "Method-U (ATCB cross-loadings)"),
        chi_sq = round(
            c(baseline_fm["chisq.scaled"], method_u_fm["chisq.scaled"]), 2
        ),
        df = c(baseline_fm["df.scaled"], method_u_fm["df.scaled"]),
        cfi = round(
            c(baseline_fm["cfi.robust"], method_u_fm["cfi.robust"]), 3
        ),
        rmsea = round(
            c(baseline_fm["rmsea.robust"], method_u_fm["rmsea.robust"]), 3
        ),
        srmr_within = round(
            c(baseline_fm["srmr_within"], method_u_fm["srmr_within"]), 3
        ),
        srmr_between = round(
            c(baseline_fm["srmr_between"], method_u_fm["srmr_between"]), 3
        ),
        delta_chisq = c(NA_real_, round(u_chisq, 2)),
        delta_df = c(NA_integer_, as.integer(u_df)),
        p_diff = c(NA_real_, round(u_p, 4))
    )

    marker_lrt_df <- tibble::tibble(
        comparison     = "Baseline vs. Method-U (ATCB cross-loadings at L1)",
        delta_chisq_sb = round(u_chisq, 3),
        delta_df       = as.integer(u_df),
        p_value        = round(u_p, 4),
        conclusion     = method_u_result
    )
} else {
    log_msg("  Method-U did not converge; marker technique not evaluated")
}

# --- [5d] Method-R: conditional on Method-U significance --------------------
method_r_result <- "not_run"

if (method_u_result == "significant" && !is.null(mcfa_method_u_fit)) {
    log_msg("  [5d] Method-U significant: fitting Method-R (fixed L1 factor covariances)")

    pe_base <- lavaan::parameterEstimates(mcfa_l1_fit)
    l1_fcovs <- pe_base |>
        dplyr::filter(
            op == "~~", lhs != rhs, level == 1L,
            lhs %in% l1_factors, rhs %in% l1_factors
        )

    fxd_lines <- vapply(
        seq_len(nrow(l1_fcovs)),
        function(i) {
            sprintf(
                "    %s ~~ %.6f * %s",
                l1_fcovs$lhs[i], l1_fcovs$est[i], l1_fcovs$rhs[i]
            )
        },
        character(1)
    )

    method_r_lines <- c(
        "level: 1",
        "    PF      =~ pf1 + pf2 + pf4 + pf5 + pf6",
        "    CW      =~ cw1 + cw2 + cw3 + cw4 + cw5",
        "    EE      =~ ee1 + ee2 + ee3",
        "    NF_COMP =~ comp1 + comp2 + comp3 + comp4",
        "    NF_AUTO =~ auto1 + auto2 + auto3 + auto4",
        "    NF_REL  =~ relt1 + relt2 + relt3 + relt4",
        "    ATCB    =~ atcb2 + atcb5 + atcb6 + atcb7",
        paste0("    ATCB    =~ ", paste(l1_subst_items, collapse = " + ")),
        fxd_lines,
        "level: 2",
        "    PF      =~ pf1 + pf2 + pf4 + pf5 + pf6",
        "    CW      =~ cw1 + cw2 + cw3 + cw4 + cw5",
        "    EE      =~ ee1 + ee2 + ee3",
        "    NF_COMP =~ comp1 + comp2 + comp3 + comp4",
        "    NF_AUTO =~ auto1 + auto2 + auto3 + auto4",
        "    NF_REL  =~ relt1 + relt2 + relt3 + relt4",
        "    ATCB    =~ atcb2 + atcb5 + atcb6 + atcb7"
    )
    mcfa_method_r_model <- paste(method_r_lines, collapse = "\n")

    method_r_fit <- tryCatch(
        lavaan::cfa(
            model        = mcfa_method_r_model,
            data         = df_l1_items,
            cluster      = "id",
            estimator    = "MLR",
            optim.method = "nlminb"
        ),
        error = function(e) {
            log_msg("  WARNING: Method-R error: ", conditionMessage(e))
            NULL
        }
    )

    if (!is.null(method_r_fit) && isTRUE(lavaan::lavInspect(method_r_fit, "converged"))) {
        lrt_r <- lavaan::lavTestLRT(
            method_r_fit, mcfa_method_u_fit,
            method = "satorra.bentler.2010"
        )
        r_chisq <- lrt_r[2, "Chisq diff"]
        r_df <- lrt_r[2, "Df diff"]
        r_p <- lrt_r[2, "Pr(>Chisq)"]
        method_r_result <- if (!is.na(r_p) && r_p < 0.05) "biased" else "unbiased"

        log_msg(
            "  Method-R SB chi-sq diff: ", round(r_chisq, 3),
            ", p = ", round(r_p, 4),
            "  -> relationships: ", method_r_result
        )

        method_r_fm <- lavaan::fitMeasures(
            method_r_fit,
            c(
                "chisq.scaled", "df.scaled", "cfi.robust", "rmsea.robust",
                "srmr_within", "srmr_between"
            )
        )

        marker_fit_df <- dplyr::bind_rows(
            marker_fit_df,
            tibble::tibble(
                model        = "Method-R (ATCB cross-loadings + fixed L1 cors)",
                chi_sq       = round(method_r_fm["chisq.scaled"], 2),
                df           = method_r_fm["df.scaled"],
                cfi          = round(method_r_fm["cfi.robust"], 3),
                rmsea        = round(method_r_fm["rmsea.robust"], 3),
                srmr_within  = round(method_r_fm["srmr_within"], 3),
                srmr_between = round(method_r_fm["srmr_between"], 3),
                delta_chisq  = round(r_chisq, 2),
                delta_df     = as.integer(r_df),
                p_diff       = round(r_p, 4)
            )
        )

        marker_lrt_df <- dplyr::bind_rows(
            marker_lrt_df,
            tibble::tibble(
                comparison     = "Method-U vs. Method-R (fixed L1 factor covariances)",
                delta_chisq_sb = round(r_chisq, 3),
                delta_df       = as.integer(r_df),
                p_value        = round(r_p, 4),
                conclusion     = method_r_result
            )
        )
    }
} else if (method_u_result == "not_significant") {
    log_msg("  [5d] Method-U not significant; Method-R not needed")
    method_r_result <- "not_needed"
}

log_msg(
    "  Marker result: Method-U = ", method_u_result,
    "; Method-R = ", method_r_result
)


# =============================================================================
# [6] SAVE OUTPUTS
# =============================================================================
log_msg("=== [6] Saving outputs ===")

fit_indices <- dplyr::bind_rows(l2_fit_df, l1_fit_df)
readr::write_csv(fit_indices, file.path(FIGS_DIR, "cfa_01_fit_indices.csv"))
save_md(fit_indices, file.path(FIGS_DIR, "cfa_01_fit_indices.md"))
log_msg("Saved: cfa_01_fit_indices")

readr::write_csv(l2_loadings, file.path(FIGS_DIR, "cfa_02_loadings_l2.csv"))
save_md(l2_loadings, file.path(FIGS_DIR, "cfa_02_loadings_l2.md"))
log_msg("Saved: cfa_02_loadings_l2")

readr::write_csv(l1_loadings_raw, file.path(FIGS_DIR, "cfa_03_loadings_l1.csv"))
save_md(l1_loadings_raw, file.path(FIGS_DIR, "cfa_03_loadings_l1.md"))
log_msg("Saved: cfa_03_loadings_l1")

omega_all <- dplyr::bind_rows(l2_omega_df, l1_omega_df)
readr::write_csv(omega_all, file.path(FIGS_DIR, "cfa_04_omega.csv"))
save_md(omega_all, file.path(FIGS_DIR, "cfa_04_omega.md"))
log_msg("Saved: cfa_04_omega")

if (!is.null(marker_evidence_df)) {
    readr::write_csv(marker_evidence_df, file.path(FIGS_DIR, "cfa_05_marker_evidence.csv"))
    save_md(marker_evidence_df, file.path(FIGS_DIR, "cfa_05_marker_evidence.md"))
    log_msg("Saved: cfa_05_marker_evidence")
}

if (!is.null(marker_fit_df)) {
    readr::write_csv(marker_fit_df, file.path(FIGS_DIR, "cfa_06_marker_fit.csv"))
    save_md(marker_fit_df, file.path(FIGS_DIR, "cfa_06_marker_fit.md"))
    log_msg("Saved: cfa_06_marker_fit")
}

if (!is.null(marker_lrt_df)) {
    readr::write_csv(marker_lrt_df, file.path(FIGS_DIR, "cfa_07_marker_lrt.csv"))
    save_md(marker_lrt_df, file.path(FIGS_DIR, "cfa_07_marker_lrt.md"))
    log_msg("Saved: cfa_07_marker_lrt")
}


# =============================================================================
# [7] SUMMARY
# =============================================================================
log_msg("=== [7] Summary ===")
log_msg("Single-item measures excluded from CFA (omega not estimable):")
log_msg("  - Job Satisfaction (js1): 1 item, L2 only (tp1/9AM)")
log_msg("  - Job Insecurity (jis1): 1 item, L2 only")
log_msg("  - Turnover Intention (turnover_intention): 1 item, L1")
log_msg("Two-item L2 factor included in CFA:")
log_msg("  - Desirability of Movement (DES): des1 + des2; just-identified factor (0 df), omega estimable")
log_msg("PF: 5-item model (pf3 excluded; absent at tp2/tp3 by survey design)")
log_msg("Marker technique: Level 1 only (L2 scales collected at separate intake session)")
log_msg("=== Measurement model complete. Output -> ", FIGS_DIR, " ===")
