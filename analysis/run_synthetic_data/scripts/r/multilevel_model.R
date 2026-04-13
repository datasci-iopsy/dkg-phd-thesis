#!/usr/bin/env Rscript
# =============================================================================
# analysis/run_synthetic_data/scripts/r/multilevel_model.R
#
# Multilevel Model Building Sequence for Turnover Intentions
# Following dissertation proposal (Curran & Bauer 2011; Enders & Tofighi 2007)
#
# Design : ~800 participants (L2) x 3 within-day timepoints (L1)
# DV     : turnover_intention_mean (1-5 ordinal, treated as continuous)
# Output : CSVs + SVGs -> analysis/run_synthetic_data/figs/mlm/
#
# Hypotheses:
#   H1a  : WP burnout facets (pf, cw, ee) -> TI (+)              [M3]
#   H1b  : WP NF facets (comp, auto, relt) -> TI (+)             [M3]
#   H2a  : BP burnout facet means -> TI (+)                       [M4]
#   H2b  : BP NF facet means -> TI (+)                            [M4]
#   H3a-c: BP breach (+), violation (+), job satisfaction (-) -> TI [M5]
#   H4a  : WP meeting count -> TI (+); moderates burnout/NF -> TI  [M3, M7a]
#   H4b  : WP meeting time -> TI (+); moderates burnout/NF -> TI   [M3, M7b]
#
# Phase 1 (M0-M2) : Variance partitioning and time trend baselines
# Phase 2 (M3)    : WP main effects — L1 facets (H1a, H1b, H4a-b main effects)
# Phase 3 (M4)    : BP mean components of L1 variables (H2a, H2b)
# Phase 4 (M5)    : L2 study variables: breach, violation, JS (H3a-c)
# Phase 5 (M6)    : Demographic sensitivity — data-driven covariate selection
# Phase 6 (M7a-b) : L1 x L1 moderation — meetings x burnout/NF composites (H4a-b)
# Phase 7         : ICC-beta (rho_beta) slope heterogeneity
#
# Centering: Enders & Tofighi (2007) / Curran & Bauer (2011)
#   - L1 predictors: person-mean centered (within) + grand-mean centered
#     person means (between) via datawizard::demean()
#   - L2 predictors: grand-mean centered
#   - ATCB: CWC-decomposed but excluded from MLM formulas (CFA marker only)
#   - Phase 6 composites: burnout_mean, nf_mean -> CWC decomposition
#
# Estimation:
#   - ML  for likelihood ratio tests
#   - REML for final parameter reporting
# =============================================================================

# --- [0] Libraries and setup -------------------------------------------------
library(lme4)
library(lmerTest)
library(broom.mixed)
library(performance)
library(parameters)
library(effectsize)
library(datawizard)
library(car)
library(ggplot2)
library(patchwork)
library(gridExtra)
library(dplyr)
library(tidyr)
library(purrr)
library(readr)
library(tibble)
library(stringr)
library(forcats)
library(here)
library(glue)
library(iccbeta)
library(interactions)

options(tibble.width = Inf)
here::here()

# Source shared utilities (log_msg, ensure_dir, theme_apa, save_svg, mlm helpers)
source(here::here("analysis", "shared", "utils", "common_utils.r"))
source(here::here("analysis", "shared", "utils", "plot_utils.r"))
source(here::here("analysis", "shared", "utils", "mlm_utils.r"))

# --- Global settings ----------------------------------------------------------
FIGS_DIR <- here::here("analysis", "run_synthetic_data", "figs", "mlm")
ensure_dir(FIGS_DIR)

theme_set(theme_apa)

# SVG save helper (binds FIGS_DIR for convenience at call sites)
save_fig <- function(plot, filename, width = 10, height = 7) {
    save_svg(plot, file.path(FIGS_DIR, filename), width, height)
}

# PDF save helper for table outputs (tableGrob-based ggplots)
save_tbl <- function(plot, filename, width = 12, height = 8) {
    path <- file.path(FIGS_DIR, filename)
    ggplot2::ggsave(path, plot = plot, device = "pdf", width = width, height = height)
    invisible(path)
}

# Default optimizer control for lmer
CTRL <- lmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 200000))

log_msg("=== MULTILEVEL MODEL BUILDING SEQUENCE ===")
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

n_participants <- dplyr::n_distinct(df_raw$response_id)
log_msg("Participants (L2): ", n_participants)
log_msg("Timepoints  (L1) : ", max(df_raw$timepoint))

# Variable name vectors
l1_predictor_vars <- c(
    "pf_mean", "cw_mean", "ee_mean",
    "comp_mean", "auto_mean", "relt_mean",
    "meetings_count", "meetings_mins"
)
# ATCB is the CFA marker variable (lavaan measurement model only).
# It is CWC-decomposed below to keep the data frame consistent, but it is
# NOT included in any MLM formula.
l1_marker_var <- "atcb_mean"
l1_all_center <- l1_predictor_vars

l2_study_vars <- c("pa_mean", "na_mean", "br_mean", "vio_mean", "js_mean")
l2_demo_vars <- c("age", "gender", "job_tenure", "is_remote", "edu_lvl", "ethnicity")

dv <- "turnover_intention_mean"

# Pretty labels for output tables
var_labels <- c(
    pf_mean = "Physical Fatigue", cw_mean = "Cognitive Weariness",
    ee_mean = "Emotional Exhaustion", comp_mean = "NF: Competence",
    auto_mean = "NF: Autonomy", relt_mean = "NF: Relatedness",
    atcb_mean = "ATCB (Marker)",
    meetings_count = "Meeting Count", meetings_mins = "Meeting Minutes",
    pa_mean = "Positive Affect", na_mean = "Negative Affect",
    br_mean = "PC Breach", vio_mean = "PC Violation",
    js_mean = "Job Satisfaction",
    turnover_intention_mean = "Turnover Intention"
)


# =============================================================================
# [2] CENTERING AND VARIABLE PREPARATION
# =============================================================================
log_msg("=== [2] Centering and variable preparation ===")

# 2a. Time centering: 0, 1, 2 (intercept = first timepoint)
df <- df_raw |>
    dplyr::mutate(time_c = timepoint - 1)

# 2b. L1 predictor centering: WP/BP decomposition via datawizard::demean()
#     Creates {var}_within (person-mean centered) and {var}_between
#     (grand-mean centered person mean) for each variable.
log_msg("  Applying person-mean centering (CWC) for L1 predictors...")
df <- datawizard::demean(
    df,
    select = l1_all_center,
    by = "response_id"
)
# CWC-decompose ATCB separately so columns exist for CFA/descriptive use,
# but atcb_mean_within/between are excluded from all MLM formulas below.
df <- datawizard::demean(df, select = l1_marker_var, by = "response_id")

# Verify centering worked: within-person means should be ~0 per person
centering_check <- verify_centering(
    df,
    id_col      = "response_id",
    within_vars = paste0(l1_predictor_vars, "_within")
)
log_msg(
    "  Max within-person mean deviation: ",
    round(centering_check$max_deviation, 8),
    " (should be ~0)"
)
if (!centering_check$all_pass) {
    stop("Centering verification failed — check datawizard::demean() output")
}

# 2c. L2 study variables: grand-mean center
for (v in l2_study_vars) {
    new_name <- paste0(v, "_c")
    df[[new_name]] <- df[[v]] - mean(df[[v]], na.rm = TRUE)
}

# 2d. Demographics: center age, factor-code categoricals
df <- df |>
    dplyr::mutate(
        age_c      = age - mean(age, na.rm = TRUE),
        gender     = factor(gender),
        job_tenure = factor(job_tenure),
        is_remote  = as.integer(is_remote),
        edu_lvl    = factor(edu_lvl),
        ethnicity  = factor(ethnicity)
    )

# 2e. Phase 6 composites (burnout_mean, nf_mean) — used exclusively in M7a/M7b
#     Create from raw facet scores, then CWC-decompose via datawizard::demean().
log_msg("  Creating Phase 6 composites (burnout_mean, nf_mean)...")
df$burnout_mean <- rowMeans(df[, c("pf_mean", "cw_mean", "ee_mean")], na.rm = TRUE)
df$nf_mean <- rowMeans(df[, c("comp_mean", "auto_mean", "relt_mean")], na.rm = TRUE)
df <- datawizard::demean(df, select = c("burnout_mean", "nf_mean"), by = "response_id")
log_msg("  Composites created: burnout_mean_within/between, nf_mean_within/between")

log_msg("  Centering complete. Total columns: ", ncol(df))


# =============================================================================
# [3] HELPER FUNCTIONS
# =============================================================================
# Modeling helpers (safe_lmer, extract_model_summary, compare_models,
# check_vif, save_vif_plot, compute_standardized_coefs,
# compute_level_specific_es, compute_delta_r2, verify_centering,
# select_covariates_bivariate) are sourced from:
#   analysis/shared/utils/mlm_utils.r
#
# Script-specific helpers below: check_assumptions, get_coef_result
# =============================================================================

#' Generate 4-panel residual diagnostic SVG
check_assumptions <- function(fit, model_name) {
    if (is.null(fit)) {
        return(invisible(NULL))
    }

    resids <- residuals(fit)
    fitted_vals <- fitted(fit)
    re <- ranef(fit)$response_id

    # Panel 1: L1 residual QQ
    p1 <- ggplot(data.frame(r = resids), aes(sample = r)) +
        stat_qq(alpha = 0.3, size = 0.8) +
        stat_qq_line(color = "red") +
        labs(title = "L1 Residual QQ Plot", x = "Theoretical", y = "Sample")

    # Panel 2: Residuals vs fitted
    p2 <- ggplot(
        data.frame(fitted = fitted_vals, resid = resids),
        aes(x = fitted, y = resid)
    ) +
        geom_point(alpha = 0.2, size = 0.8) +
        geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
        geom_smooth(
            method = "loess", se = FALSE, color = "blue",
            linewidth = 0.6
        ) +
        labs(title = "Residuals vs. Fitted", x = "Fitted", y = "Residual")

    # Panel 3: Random intercept QQ
    p3 <- ggplot(data.frame(ri = re[["(Intercept)"]]), aes(sample = ri)) +
        stat_qq(alpha = 0.5, size = 0.8) +
        stat_qq_line(color = "red") +
        labs(
            title = "Random Intercept QQ Plot",
            x = "Theoretical", y = "Sample"
        )

    # Panel 4: Scale-location
    p4 <- ggplot(
        data.frame(
            fitted = fitted_vals,
            sqrt_abs_resid = sqrt(abs(resids))
        ),
        aes(x = fitted, y = sqrt_abs_resid)
    ) +
        geom_point(alpha = 0.2, size = 0.8) +
        geom_smooth(
            method = "loess", se = FALSE, color = "blue",
            linewidth = 0.6
        ) +
        labs(
            title = "Scale-Location",
            x = "Fitted", y = expression(sqrt("|Residual|"))
        )

    combined <- (p1 | p2) / (p3 | p4) +
        patchwork::plot_annotation(
            title = paste("Model Diagnostics:", model_name),
            theme = theme(plot.title = element_text(face = "bold", size = 14))
        )

    filename <- paste0(
        "mlm_diag_",
        gsub("[^a-z0-9]+", "_", tolower(model_name)), ".svg"
    )
    save_fig(combined, filename, width = 12, height = 9)
}



# =============================================================================
# [4] MODEL 0: UNCONDITIONAL MEANS (EMPTY/NULL)
# =============================================================================
log_msg("=== [4] Model 0: Unconditional Means ===")
log_msg("  Design prerequisite: ICC justifies MLM (> 0.05 threshold)")
log_msg("  Formula: TI ~ 1 + (1 | response_id)")

m0_reml <- safe_lmer(turnover_intention_mean ~ 1 + (1 | response_id),
    data = df, REML = TRUE
)
m0_ml <- safe_lmer(turnover_intention_mean ~ 1 + (1 | response_id),
    data = df, REML = FALSE
)

# ICC
icc_m0 <- performance::icc(m0_reml)
log_msg("  ICC (adjusted)  = ", round(icc_m0$ICC_adjusted, 4))
log_msg("  ICC (conditional) = ", round(icc_m0$ICC_conditional, 4))

# Variance components
vc_m0 <- as.data.frame(VarCorr(m0_reml))
tau_00 <- vc_m0$vcov[vc_m0$grp == "response_id"]
sigma2 <- vc_m0$vcov[vc_m0$grp == "Residual"]
log_msg("  tau_00 (between) = ", round(tau_00, 4))
log_msg("  sigma2 (within)  = ", round(sigma2, 4))
log_msg("  Grand mean TI    = ", round(fixef(m0_reml)[1], 4))
log_msg(
    "  ICC result: ICC = ", round(icc_m0$ICC_adjusted, 4),
    " -> MLM ", ifelse(icc_m0$ICC_adjusted > 0.05, "JUSTIFIED", "marginal"),
    " (>0.05 threshold)"
)

m0_summary <- extract_model_summary(m0_reml, "Model 0: Unconditional Means")


# =============================================================================
# [5] MODEL 1: UNCONDITIONAL GROWTH - FIXED TIME
# =============================================================================
log_msg("=== [5] Model 1: Unconditional Growth (Fixed Slope) ===")
log_msg("  Structural baseline: fixed time trend (occasions coded 0, 1, 2)")
log_msg("  Formula: TI ~ time_c + (1 | response_id)")

m1_reml <- safe_lmer(turnover_intention_mean ~ time_c + (1 | response_id),
    data = df, REML = TRUE
)
m1_ml <- safe_lmer(turnover_intention_mean ~ time_c + (1 | response_id),
    data = df, REML = FALSE
)

# LRT: Model 1 vs Model 0
lrt_1v0 <- compare_models(m0_ml, m1_ml, "Model 0", "Model 1")
log_msg(
    "  LRT Model 1 vs 0: chi2 = ", round(lrt_1v0$chi_sq, 3),
    ", df = ", lrt_1v0$df, ", p = ", format.pval(lrt_1v0$p_value, digits = 4)
)

time_coef <- fixef(m1_reml)["time_c"]
log_msg("  time_c coefficient = ", round(time_coef, 4))
log_msg(
    "  Baseline time trend: time_c = ", round(time_coef, 4),
    " -> ", ifelse(time_coef > 0 && lrt_1v0$p_value < 0.05,
        "POSITIVE (p < .05)",
        "not significant or negative"
    )
)

m1_summary <- extract_model_summary(m1_reml, "Model 1: Fixed Time")


# =============================================================================
# [6] MODEL 2: UNCONDITIONAL GROWTH - RANDOM SLOPE
# =============================================================================
log_msg("=== [6] Model 2: Unconditional Growth (Random Slope) ===")
log_msg("  Structural baseline: evaluating random slope variance (tau11)")
log_msg("  ICC-beta replaces formal significance test (3-timepoint limitation)")
log_msg("  Formula: TI ~ time_c + (time_c | response_id)")

# Try full random slope (correlated)
m2_reml <- safe_lmer(
    turnover_intention_mean ~ time_c + (time_c | response_id),
    data = df, REML = TRUE
)
m2_ml <- safe_lmer(
    turnover_intention_mean ~ time_c + (time_c | response_id),
    data = df, REML = FALSE
)

# Fallback: uncorrelated random effects if full model is singular or failed
use_random_slope <- TRUE
re_note <- "correlated"

if (is.null(m2_reml) || isSingular(m2_reml)) {
    log_msg(
        "  [INFO] Full random slope model singular/failed. ",
        "Trying uncorrelated (time_c || response_id)..."
    )
    m2_reml <- safe_lmer(
        turnover_intention_mean ~ time_c + (time_c || response_id),
        data = df, REML = TRUE
    )
    m2_ml <- safe_lmer(
        turnover_intention_mean ~ time_c + (time_c || response_id),
        data = df, REML = FALSE
    )
    re_note <- "uncorrelated"
}

if (is.null(m2_reml) || isSingular(m2_reml)) {
    log_msg("  [INFO] Random slope not supported with 3 timepoints.")
    log_msg("  [INFO] Proceeding with random intercept only for all models.")
    use_random_slope <- FALSE
    re_note <- "intercept only"
    # Reuse Model 1 as Model 2
    m2_reml <- m1_reml
    m2_ml <- m1_ml
}

if (use_random_slope) {
    lrt_2v1 <- compare_models(m1_ml, m2_ml, "Model 1", "Model 2")
    log_msg(
        "  LRT Model 2 vs 1: chi2 = ", round(lrt_2v1$chi_sq, 3),
        ", df = ", lrt_2v1$df,
        ", p = ", format.pval(lrt_2v1$p_value, digits = 4)
    )

    # Extract random slope variance
    vc_m2 <- as.data.frame(VarCorr(m2_reml))
    tau_11_val <- vc_m2$vcov[
        vc_m2$grp == "response_id" & vc_m2$var1 == "time_c" & is.na(vc_m2$var2)
    ]
    tau_11 <- if (length(tau_11_val) > 0) tau_11_val[1] else NA

    log_msg(
        "  Random slope variance (tau_11) = ",
        ifelse(is.na(tau_11), "NA", round(tau_11, 4))
    )
    log_msg("  Random effects structure: ", re_note)

    # Re-evaluate: if LRT is not significant, drop random slope
    if (!is.na(lrt_2v1$p_value) && lrt_2v1$p_value >= 0.05) {
        log_msg("  [INFO] Random slope LRT not significant (p >= .05).")
        log_msg("  [INFO] Retaining random intercept only for parsimony.")
        use_random_slope <- FALSE
        re_note <- "intercept only (LRT ns)"
    }

    log_msg(
        "  H2b result: tau_11 = ",
        ifelse(is.na(tau_11), "NA", round(tau_11, 4)),
        " -> ", ifelse(!is.na(tau_11) && tau_11 > 0 && lrt_2v1$p_value < 0.05,
            "SUPPORTED", "NOT SUPPORTED"
        )
    )
    log_msg(
        "  H2c result: LRT p = ",
        format.pval(lrt_2v1$p_value, digits = 4),
        " -> ", ifelse(lrt_2v1$p_value < 0.05, "SUPPORTED", "NOT SUPPORTED")
    )
} else {
    lrt_2v1 <- tibble::tibble(
        comparison = "Model 2 vs Model 1",
        chi_sq = NA_real_, df = NA_integer_, p_value = NA_real_
    )
    log_msg("  H2b result: NOT SUPPORTED (random slope not estimable)")
    log_msg("  H2c result: NOT SUPPORTED (random slope not estimable)")
}

m2_summary <- extract_model_summary(m2_reml, "Model 2: Random Slope")
log_msg(
    "  Decision: use_random_slope = ", use_random_slope,
    " (", re_note, ")"
)


# =============================================================================
# [7] MODEL 3: WITHIN-PERSON (L1) PREDICTORS
# =============================================================================
log_msg("=== [7] Model 3: Within-Person (L1) Predictors ===")
log_msg("  Tests H1a (WP burnout facets), H1b (WP NF facets), H4a-b main effects (WP meetings)")

# Build formula dynamically based on random slope decision
re_term <- if (use_random_slope) "(time_c | response_id)" else "(1 | response_id)"

m3_formula <- as.formula(paste(
    "turnover_intention_mean ~ time_c +",
    "pf_mean_within + cw_mean_within + ee_mean_within +",
    "comp_mean_within + auto_mean_within + relt_mean_within +",
    "meetings_count_within + meetings_mins_within +",
    re_term
))
log_msg("  Formula: ", deparse(m3_formula, width.cutoff = 200))

m3_reml <- safe_lmer(m3_formula, data = df, REML = TRUE)
m3_ml <- safe_lmer(m3_formula, data = df, REML = FALSE)

# LRT: Model 3 vs best unconditional
m_prev_ml <- if (use_random_slope) m2_ml else m1_ml
prev_name <- if (use_random_slope) "Model 2" else "Model 1"
lrt_3vp <- compare_models(m_prev_ml, m3_ml, prev_name, "Model 3")
log_msg(
    "  LRT Model 3 vs ", prev_name, ": chi2 = ",
    round(lrt_3vp$chi_sq, 3),
    ", df = ", lrt_3vp$df, ", p = ", format.pval(lrt_3vp$p_value, digits = 4)
)

# Hypothesis tests for H1a, H1b, H4a-b main effects
fe3 <- broom.mixed::tidy(m3_reml, effects = "fixed", conf.int = TRUE)
h3_vars <- c(
    "pf_mean_within", "cw_mean_within", "ee_mean_within",
    "comp_mean_within", "auto_mean_within", "relt_mean_within",
    "meetings_count_within", "meetings_mins_within"
)
h3_labels <- c(
    "H1a:pf", "H1a:cw", "H1a:ee",
    "H1b:comp", "H1b:auto", "H1b:relt",
    "H4a:main", "H4b:main"
)
for (i in seq_along(h3_vars)) {
    row <- fe3[fe3$term == h3_vars[i], ]
    if (nrow(row) > 0) {
        log_msg(
            "  ", h3_labels[i], " (", h3_vars[i], "): b = ",
            round(row$estimate, 4), ", p = ",
            format.pval(row$p.value, digits = 4),
            " -> ", ifelse(row$estimate > 0 & row$p.value < 0.05,
                "SUPPORTED", "NOT SUPPORTED"
            )
        )
    }
}

# VIF
vif_m3 <- check_vif(m3_reml, "Model 3")
m3_summary <- extract_model_summary(m3_reml, "Model 3: L1 Within-Person")


# =============================================================================
# [8] MODEL 4: ADD BETWEEN-PERSON COMPONENTS OF L1 VARIABLES
# =============================================================================
log_msg("=== [8] Model 4: Between-Person Components of L1 Variables ===")
log_msg("  Tests H2a (BP burnout facet means -> TI), H2b (BP NF facet means -> TI)")
log_msg("  Also evaluates contextual effects (BP - WP difference)")

m4_formula <- as.formula(paste(
    "turnover_intention_mean ~ time_c +",
    "pf_mean_within + cw_mean_within + ee_mean_within +",
    "comp_mean_within + auto_mean_within + relt_mean_within +",
    "meetings_count_within + meetings_mins_within +",
    "pf_mean_between + cw_mean_between + ee_mean_between +",
    "comp_mean_between + auto_mean_between + relt_mean_between +",
    "meetings_count_between + meetings_mins_between +",
    re_term
))
log_msg("  Formula: ", deparse(m4_formula, width.cutoff = 200))

m4_reml <- safe_lmer(m4_formula, data = df, REML = TRUE)
m4_ml <- safe_lmer(m4_formula, data = df, REML = FALSE)

lrt_4v3 <- compare_models(m3_ml, m4_ml, "Model 3", "Model 4")
log_msg(
    "  LRT Model 4 vs 3: chi2 = ", round(lrt_4v3$chi_sq, 3),
    ", df = ", lrt_4v3$df, ", p = ", format.pval(lrt_4v3$p_value, digits = 4)
)

# Log contextual effects (BP - WP difference)
fe4 <- broom.mixed::tidy(m4_reml, effects = "fixed", conf.int = TRUE)
for (v in l1_predictor_vars) {
    wp_row <- fe4[fe4$term == paste0(v, "_within"), ]
    bp_row <- fe4[fe4$term == paste0(v, "_between"), ]
    if (nrow(wp_row) > 0 && nrow(bp_row) > 0) {
        ctx <- bp_row$estimate - wp_row$estimate
        log_msg(
            "  Contextual effect (", v, "): BP - WP = ",
            round(ctx, 4)
        )
    }
}

# H2a: BP burnout facet means -> TI (+)
h2a_vars <- c("pf_mean_between", "cw_mean_between", "ee_mean_between")
h2a_labels <- c("H2a:pf", "H2a:cw", "H2a:ee")
for (i in seq_along(h2a_vars)) {
    row <- fe4[fe4$term == h2a_vars[i], ]
    if (nrow(row) > 0) {
        log_msg(
            "  ", h2a_labels[i], " (", h2a_vars[i], "): b = ",
            round(row$estimate, 4), ", p = ",
            format.pval(row$p.value, digits = 4),
            " -> ", ifelse(row$estimate > 0 & row$p.value < 0.05,
                "SUPPORTED", "NOT SUPPORTED"
            )
        )
    }
}

# H2b: BP NF facet means -> TI (+)
h2b_vars <- c("comp_mean_between", "auto_mean_between", "relt_mean_between")
h2b_labels <- c("H2b:comp", "H2b:auto", "H2b:relt")
for (i in seq_along(h2b_vars)) {
    row <- fe4[fe4$term == h2b_vars[i], ]
    if (nrow(row) > 0) {
        log_msg(
            "  ", h2b_labels[i], " (", h2b_vars[i], "): b = ",
            round(row$estimate, 4), ", p = ",
            format.pval(row$p.value, digits = 4),
            " -> ", ifelse(row$estimate > 0 & row$p.value < 0.05,
                "SUPPORTED", "NOT SUPPORTED"
            )
        )
    }
}

vif_m4 <- check_vif(m4_reml, "Model 4")
m4_summary <- extract_model_summary(
    m4_reml,
    "Model 4: L1 Within + Between"
)


# =============================================================================
# [9] MODEL 5: ADD L2 STUDY VARIABLES
# =============================================================================
log_msg("=== [9] Model 5: L2 Between-Person Study Variables ===")
log_msg("  Tests H3a-c: breach/violation/JS -> TI; PA/NA entered as controls")

m5_formula <- as.formula(paste(
    "turnover_intention_mean ~ time_c +",
    "pf_mean_within + cw_mean_within + ee_mean_within +",
    "comp_mean_within + auto_mean_within + relt_mean_within +",
    "meetings_count_within + meetings_mins_within +",
    "pf_mean_between + cw_mean_between + ee_mean_between +",
    "comp_mean_between + auto_mean_between + relt_mean_between +",
    "meetings_count_between + meetings_mins_between +",
    "pa_mean_c + na_mean_c + br_mean_c + vio_mean_c + js_mean_c +",
    re_term
))
log_msg("  Formula: ", deparse(m5_formula, width.cutoff = 200))

m5_reml <- safe_lmer(m5_formula, data = df, REML = TRUE)
m5_ml <- safe_lmer(m5_formula, data = df, REML = FALSE)

lrt_5v4 <- compare_models(m4_ml, m5_ml, "Model 4", "Model 5")
log_msg(
    "  LRT Model 5 vs 4: chi2 = ", round(lrt_5v4$chi_sq, 3),
    ", df = ", lrt_5v4$df, ", p = ", format.pval(lrt_5v4$p_value, digits = 4)
)

# Hypothesis tests for H9a-c (breach, violation, JS) — PA/NA are controls
fe5 <- broom.mixed::tidy(m5_reml, effects = "fixed", conf.int = TRUE)

# Controls: PA and NA (log direction, no hypothesis label)
for (ctrl in c("pa_mean_c", "na_mean_c")) {
    row <- fe5[fe5$term == ctrl, ]
    if (nrow(row) > 0) {
        dir <- if (ctrl == "pa_mean_c") "negative" else "positive"
        log_msg(
            "  Control (", ctrl, "): b = ", round(row$estimate, 4),
            ", p = ", format.pval(row$p.value, digits = 4),
            " (expected: ", dir, ")"
        )
    }
}

h4_vars <- c("br_mean_c", "vio_mean_c", "js_mean_c")
h4_labels <- c("H3a", "H3b", "H3c")
h4_directions <- c("positive", "positive", "negative")
for (i in seq_along(h4_vars)) {
    row <- fe5[fe5$term == h4_vars[i], ]
    if (nrow(row) > 0) {
        expected <- if (h4_directions[i] == "positive") {
            row$estimate > 0
        } else {
            row$estimate < 0
        }
        log_msg(
            "  ", h4_labels[i], " (", h4_vars[i], "): b = ",
            round(row$estimate, 4), ", p = ",
            format.pval(row$p.value, digits = 4),
            " (expected: ", h4_directions[i], ")",
            " -> ", ifelse(expected & row$p.value < 0.05,
                "SUPPORTED", "NOT SUPPORTED"
            )
        )
    }
}

vif_m5 <- check_vif(m5_reml, "Model 5")
m5_summary <- extract_model_summary(
    m5_reml,
    "Model 5: L1 + L2 Study Variables"
)


# =============================================================================
# [10] MODEL 6: DEMOGRAPHIC COVARIATES — DATA-DRIVEN SELECTION
# =============================================================================
log_msg("=== [10] Model 6: Demographic Covariates (data-driven selection) ===")
log_msg("  Mandatory controls (theory-justified): age_c, job_tenure")
log_msg("  Screened via Bernerth & Aguinis (2016): gender, is_remote, edu_lvl, ethnicity")
log_msg("  Note: pa_mean_c / na_mean_c already entered in Model 5 as affect controls")

# 10a. Bivariate screening: correlate screened candidates with person-level DV mean
#      (use person-level data to avoid inflation from repeated occasions)
mandatory_covs <- c("age_c", "job_tenure")
screened_candidates <- c("gender", "is_remote", "edu_lvl", "ethnicity")

df_bp <- df |>
    dplyr::group_by(response_id) |>
    dplyr::summarise(
        ti_mean    = mean(turnover_intention_mean, na.rm = TRUE),
        age_c      = dplyr::first(age_c),
        gender     = dplyr::first(gender),
        job_tenure = dplyr::first(job_tenure),
        is_remote  = dplyr::first(is_remote),
        edu_lvl    = dplyr::first(edu_lvl),
        ethnicity  = dplyr::first(ethnicity),
        .groups = "drop"
    )

cov_screen <- select_covariates_bivariate(
    df_bp,
    dv          = "ti_mean",
    candidates  = screened_candidates,
    r_threshold = 0.10
)

log_msg("  Bivariate screening results:")
for (i in seq_len(nrow(cov_screen$cor_table))) {
    row <- cov_screen$cor_table[i, ]
    log_msg(
        "    ", row$variable, " | r = ", round(row$r, 3),
        " | p = ", format.pval(row$p, digits = 3),
        " | type: ", row$type
    )
}
log_msg("  Selected covariates (|r| >= .10): ",
    if (length(cov_screen$selected) > 0) paste(cov_screen$selected, collapse = ", ")
    else "none"
)
log_msg("  Excluded: ",
    if (length(cov_screen$excluded) > 0) paste(cov_screen$excluded, collapse = ", ")
    else "none"
)

readr::write_csv(
    cov_screen$cor_table,
    file.path(FIGS_DIR, "mlm_09_covariate_screening.csv")
)
log_msg("  Saved covariate screening CSV")

# 10b. Build M6 formula: mandatory controls always included; screened covariates
#      added only if they pass the |r| >= .10 threshold
m5_base_terms <- paste(
    "turnover_intention_mean ~ time_c +",
    "pf_mean_within + cw_mean_within + ee_mean_within +",
    "comp_mean_within + auto_mean_within + relt_mean_within +",
    "meetings_count_within + meetings_mins_within +",
    "pf_mean_between + cw_mean_between + ee_mean_between +",
    "comp_mean_between + auto_mean_between + relt_mean_between +",
    "meetings_count_between + meetings_mins_between +",
    "pa_mean_c + na_mean_c + br_mean_c + vio_mean_c + js_mean_c"
)

all_m6_covs <- c(mandatory_covs, cov_screen$selected)
log_msg("  Mandatory covariates entered: ", paste(mandatory_covs, collapse = ", "))
log_msg("  Screened covariates added (|r| >= .10): ",
    if (length(cov_screen$selected) > 0) paste(cov_screen$selected, collapse = ", ")
    else "none"
)

cov_terms  <- paste(all_m6_covs, collapse = " + ")
m6_formula <- as.formula(paste(m5_base_terms, "+", cov_terms, "+", re_term))
log_msg("  Formula: ", deparse(m6_formula, width.cutoff = 200))

m6_reml <- safe_lmer(m6_formula, data = df, REML = TRUE)
m6_ml   <- safe_lmer(m6_formula, data = df, REML = FALSE)

lrt_6v5 <- compare_models(m5_ml, m6_ml, "Model 5", "Model 6")
log_msg(
    "  LRT Model 6 vs 5: chi2 = ", round(lrt_6v5$chi_sq, 3),
    ", df = ", lrt_6v5$df, ", p = ", format.pval(lrt_6v5$p_value, digits = 4)
)
fe6 <- broom.mixed::tidy(m6_reml, effects = "fixed", conf.int = TRUE)

# 10c. Coefficient stability: flag >20% change in substantive effects
log_msg("  Checking stability of substantive effects (Model 5 -> 6):")
check_stability_vars <- c(
    h3_vars, paste0(l1_predictor_vars, "_between"),
    h4_vars
)
for (v in check_stability_vars) {
    r5 <- fe5[fe5$term == v, ]
    r6 <- fe6[fe6$term == v, ]
    if (nrow(r5) > 0 && nrow(r6) > 0) {
        change <- abs(r6$estimate - r5$estimate)
        pct_change <- ifelse(abs(r5$estimate) > 0.001,
            round(change / abs(r5$estimate) * 100, 1), NA
        )
        if (!is.na(pct_change) && pct_change > 20) {
            log_msg(
                "  [NOTE] ", v, " changed >20%: ",
                round(r5$estimate, 4), " -> ", round(r6$estimate, 4),
                " (", pct_change, "% change)"
            )
        }
    }
}

vif_m6 <- check_vif(m6_reml, "Model 6")
m6_summary <- extract_model_summary(
    m6_reml,
    "Model 6: Full Model with Covariates"
)


# =============================================================================
# [11] MODEL COMPARISON TABLE
# =============================================================================
log_msg("=== [11] Building model comparison table ===")

model_names <- c(
    "Model 0: Unconditional Means",
    "Model 1: Fixed Time",
    "Model 2: Random Slope",
    "Model 3: L1 Within-Person",
    "Model 4: L1 Within + Between",
    "Model 5: L1 + L2 Study Variables",
    "Model 6: Full Model with Covariates"
)
model_fits_reml <- list(
    m0_reml, m1_reml, m2_reml, m3_reml,
    m4_reml, m5_reml, m6_reml
)
model_fits_ml <- list(
    m0_ml, m1_ml, m2_ml, m3_ml,
    m4_ml, m5_ml, m6_ml
)

# Collect fit statistics
comparison_tbl <- purrr::map2_dfr(
    model_fits_reml, model_names,
    function(fit, name) {
        if (is.null(fit)) {
            return(tibble::tibble(Model = name))
        }
        gl <- broom.mixed::glance(fit)
        r2 <- tryCatch(performance::r2_nakagawa(fit),
            error = function(e) list(R2_marginal = NA, R2_conditional = NA)
        )
        vc <- as.data.frame(VarCorr(fit))

        tau_00_val <- vc$vcov[
            vc$grp == "response_id" & vc$var1 == "(Intercept)" & is.na(vc$var2)
        ]
        if (length(tau_00_val) == 0) tau_00_val <- NA
        sigma2_val <- vc$vcov[vc$grp == "Residual"]
        if (length(sigma2_val) == 0) sigma2_val <- NA
        tau_11_val <- vc$vcov[
            vc$grp == "response_id" & vc$var1 == "time_c" & is.na(vc$var2)
        ]
        if (length(tau_11_val) == 0) tau_11_val <- NA

        tibble::tibble(
            Model          = name,
            AIC            = gl$AIC,
            BIC            = gl$BIC,
            logLik         = gl$logLik,
            deviance       = if ("deviance" %in% names(gl)) gl$deviance else NA_real_,
            n_fixed        = length(fixef(fit)),
            R2_marginal    = r2$R2_marginal,
            R2_conditional = r2$R2_conditional,
            tau_00         = tau_00_val,
            tau_11         = tau_11_val,
            sigma2         = sigma2_val
        )
    }
)

# Add LRT results
lrt_all <- dplyr::bind_rows(
    tibble::tibble(
        Model = model_names[1], LRT_chi2 = NA, LRT_df = NA,
        LRT_p = NA
    ),
    lrt_1v0 |> dplyr::transmute(
        Model = model_names[2],
        LRT_chi2 = chi_sq, LRT_df = df, LRT_p = p_value
    ),
    lrt_2v1 |> dplyr::transmute(
        Model = model_names[3],
        LRT_chi2 = chi_sq, LRT_df = df, LRT_p = p_value
    ),
    lrt_3vp |> dplyr::transmute(
        Model = model_names[4],
        LRT_chi2 = chi_sq, LRT_df = df, LRT_p = p_value
    ),
    lrt_4v3 |> dplyr::transmute(
        Model = model_names[5],
        LRT_chi2 = chi_sq, LRT_df = df, LRT_p = p_value
    ),
    lrt_5v4 |> dplyr::transmute(
        Model = model_names[6],
        LRT_chi2 = chi_sq, LRT_df = df, LRT_p = p_value
    ),
    lrt_6v5 |> dplyr::transmute(
        Model = model_names[7],
        LRT_chi2 = chi_sq, LRT_df = df, LRT_p = p_value
    )
)

comparison_tbl <- dplyr::left_join(comparison_tbl, lrt_all, by = "Model")

readr::write_csv(
    comparison_tbl,
    file.path(FIGS_DIR, "mlm_01_model_comparison.csv")
)
log_msg("  Saved model comparison CSV")

# SVG table
comparison_display <- comparison_tbl |>
    dplyr::mutate(across(where(is.numeric), ~ round(., 3)))
p_comp_grob <- gridExtra::tableGrob(comparison_display,
    rows = NULL,
    theme = gridExtra::ttheme_minimal(base_size = 8)
)
p_comp <- ggplot2::ggplot() +
    ggplot2::annotation_custom(p_comp_grob) +
    ggplot2::theme_void()
save_tbl(p_comp, "mlm_01_model_comparison.pdf", width = 18, height = 6)
log_msg("  Saved model comparison PDF")


# =============================================================================
# [12] FIXED EFFECTS SUMMARY TABLE
# =============================================================================
log_msg("=== [12] Building fixed effects summary ===")

fe_all <- purrr::map2_dfr(model_fits_reml, model_names, function(fit, name) {
    if (is.null(fit)) {
        return(tibble::tibble(model = name))
    }
    broom.mixed::tidy(fit,
        effects = "fixed", conf.int = TRUE,
        conf.level = 0.95
    ) |>
        dplyr::mutate(model = name)
})

readr::write_csv(fe_all, file.path(FIGS_DIR, "mlm_02_fixed_effects.csv"))
log_msg("  Saved fixed effects CSV")

# SVG: one file per model
for (i in seq_along(model_names)) {
    sub_tbl <- fe_all |>
        dplyr::filter(model == model_names[i]) |>
        dplyr::select(
            term, estimate, std.error, statistic, df, p.value,
            conf.low, conf.high
        ) |>
        dplyr::mutate(across(where(is.numeric), ~ round(., 4)))

    grob <- gridExtra::tableGrob(
        sub_tbl,
        rows = NULL,
        theme = gridExtra::ttheme_minimal(base_size = 9)
    )
    p_sub <- ggplot2::ggplot() +
        ggplot2::annotation_custom(grob) +
        ggplot2::labs(title = model_names[i]) +
        ggplot2::theme_void() +
        ggplot2::theme(plot.title = ggplot2::element_text(
            face = "bold", size = 12, hjust = 0.5
        ))
    filename <- paste0(
        "mlm_02_fixed_effects_",
        gsub("[^a-z0-9]+", "_", tolower(model_names[i])), ".pdf"
    )
    save_tbl(p_sub, filename, width = 14, height = max(4, nrow(sub_tbl) * 0.4))
}
log_msg("  Saved fixed effects SVGs")


# =============================================================================
# [13] RANDOM EFFECTS SUMMARY TABLE
# =============================================================================
log_msg("=== [13] Building random effects summary ===")

re_all <- purrr::map2_dfr(model_fits_reml, model_names, function(fit, name) {
    if (is.null(fit)) {
        return(tibble::tibble(model = name))
    }
    broom.mixed::tidy(fit, effects = "ran_pars") |>
        dplyr::mutate(model = name)
})

readr::write_csv(re_all, file.path(FIGS_DIR, "mlm_03_random_effects.csv"))
log_msg("  Saved random effects CSV")

re_display <- re_all |>
    dplyr::mutate(across(where(is.numeric), ~ round(., 4)))
re_grob <- gridExtra::tableGrob(re_display,
    rows = NULL,
    theme = gridExtra::ttheme_minimal(base_size = 9)
)
p_re <- ggplot2::ggplot() +
    ggplot2::annotation_custom(re_grob) +
    ggplot2::theme_void()
save_tbl(p_re, "mlm_03_random_effects.pdf", width = 12, height = 8)
log_msg("  Saved random effects PDF")


# =============================================================================
# [14] HYPOTHESIS TESTING SUMMARY
# =============================================================================
log_msg("=== [14] Building hypothesis testing summary ===")

hyp_tbl <- tibble::tribble(
    ~Hypothesis,  ~Description,                                      ~Test,                          ~Model,
    # --- Design prerequisite ---
    "Prereq",     "Between-person variance in TI",                   "ICC > 0.05",                   "Model 0",
    # --- H1a: WP burnout facets ---
    "H1a:pf",     "Physical fatigue -> TI (+, WP)",                  "pf_mean_within > 0",           "Model 3",
    "H1a:cw",     "Cognitive weariness -> TI (+, WP)",               "cw_mean_within > 0",           "Model 3",
    "H1a:ee",     "Emotional exhaustion -> TI (+, WP)",              "ee_mean_within > 0",           "Model 3",
    # --- H1b: WP NF facets ---
    "H1b:comp",   "Competence frustration -> TI (+, WP)",            "comp_mean_within > 0",         "Model 3",
    "H1b:auto",   "Autonomy frustration -> TI (+, WP)",              "auto_mean_within > 0",         "Model 3",
    "H1b:relt",   "Relatedness frustration -> TI (+, WP)",           "relt_mean_within > 0",         "Model 3",
    # --- H2a: BP burnout facet means ---
    "H2a:pf",     "BP physical fatigue mean -> TI (+)",              "pf_mean_between > 0",          "Model 4",
    "H2a:cw",     "BP cognitive weariness mean -> TI (+)",           "cw_mean_between > 0",          "Model 4",
    "H2a:ee",     "BP emotional exhaustion mean -> TI (+)",          "ee_mean_between > 0",          "Model 4",
    # --- H2b: BP NF facet means ---
    "H2b:comp",   "BP competence frustration mean -> TI (+)",        "comp_mean_between > 0",        "Model 4",
    "H2b:auto",   "BP autonomy frustration mean -> TI (+)",          "auto_mean_between > 0",        "Model 4",
    "H2b:relt",   "BP relatedness frustration mean -> TI (+)",       "relt_mean_between > 0",        "Model 4",
    # --- H3a-c: L2 study variables ---
    "H3a",        "PC breach -> TI (+, BP)",                         "br_mean_c > 0",                "Model 5",
    "H3b",        "PC violation -> TI (+, BP)",                      "vio_mean_c > 0",               "Model 5",
    "H3c",        "Job satisfaction -> TI (-, BP)",                  "js_mean_c < 0",                "Model 5",
    # --- H4a: Meeting count main effect + moderation ---
    "H4a:main",   "Meeting count -> TI (+, WP)",                     "meetings_count_within > 0",    "Model 3",
    "H4a:burn",   "Mtg count x burnout composite (WP)",              "interaction p < .05",          "Model 7a",
    "H4a:nf",     "Mtg count x NF composite (WP)",                   "interaction p < .05",          "Model 7a",
    # --- H4b: Meeting time main effect + moderation ---
    "H4b:main",   "Meeting time -> TI (+, WP)",                      "meetings_mins_within > 0",     "Model 3",
    "H4b:burn",   "Mtg time x burnout composite (WP)",               "interaction p < .05",          "Model 7b",
    "H4b:nf",     "Mtg time x NF composite (WP)",                    "interaction p < .05",          "Model 7b"
)

# Pull test results — lookup by hypothesis label and term name
get_coef_result <- function(fe_tbl, model_name, term_name, direction) {
    row <- fe_tbl |>
        dplyr::filter(model == model_name, term == term_name)
    if (nrow(row) == 0) {
        return(list(est = NA, p = NA, supported = NA))
    }
    est <- row$estimate[1]
    p <- row$p.value[1]
    dir_ok <- if (direction == "+") est > 0 else est < 0
    supported <- dir_ok & p < 0.05
    list(est = round(est, 4), p = p, supported = supported)
}

hyp_results <- hyp_tbl |>
    dplyr::mutate(
        Estimate  = NA_real_,
        p_value   = NA_real_,
        Supported = NA_character_
    )

# Helper to find row index by hypothesis label
hyp_idx <- function(label) which(hyp_results$Hypothesis == label)

# Design prerequisite (ICC)
hyp_results$Estimate[hyp_idx("Prereq")]  <- round(icc_m0$ICC_adjusted, 4)
hyp_results$p_value[hyp_idx("Prereq")]   <- NA
hyp_results$Supported[hyp_idx("Prereq")] <- ifelse(
    icc_m0$ICC_adjusted > 0.05, "Yes", "No"
)

# H1a: WP burnout facets (M3)
h1a_map <- list(
    "H1a:pf" = "pf_mean_within",
    "H1a:cw" = "cw_mean_within",
    "H1a:ee" = "ee_mean_within"
)
for (lbl in names(h1a_map)) {
    r <- get_coef_result(fe_all, "Model 3: L1 Within-Person", h1a_map[[lbl]], "+")
    hyp_results$Estimate[hyp_idx(lbl)]  <- r$est
    hyp_results$p_value[hyp_idx(lbl)]   <- r$p
    hyp_results$Supported[hyp_idx(lbl)] <- ifelse(isTRUE(r$supported), "Yes", "No")
}

# H1b: WP NF facets (M3)
h1b_map <- list(
    "H1b:comp" = "comp_mean_within",
    "H1b:auto" = "auto_mean_within",
    "H1b:relt" = "relt_mean_within"
)
for (lbl in names(h1b_map)) {
    r <- get_coef_result(fe_all, "Model 3: L1 Within-Person", h1b_map[[lbl]], "+")
    hyp_results$Estimate[hyp_idx(lbl)]  <- r$est
    hyp_results$p_value[hyp_idx(lbl)]   <- r$p
    hyp_results$Supported[hyp_idx(lbl)] <- ifelse(isTRUE(r$supported), "Yes", "No")
}

# H2a: BP burnout facet means (M4)
h2a_map <- list(
    "H2a:pf" = "pf_mean_between",
    "H2a:cw" = "cw_mean_between",
    "H2a:ee" = "ee_mean_between"
)
for (lbl in names(h2a_map)) {
    r <- get_coef_result(fe_all, "Model 4: L1 Within + Between", h2a_map[[lbl]], "+")
    hyp_results$Estimate[hyp_idx(lbl)]  <- r$est
    hyp_results$p_value[hyp_idx(lbl)]   <- r$p
    hyp_results$Supported[hyp_idx(lbl)] <- ifelse(isTRUE(r$supported), "Yes", "No")
}

# H2b: BP NF facet means (M4)
h2b_map <- list(
    "H2b:comp" = "comp_mean_between",
    "H2b:auto" = "auto_mean_between",
    "H2b:relt" = "relt_mean_between"
)
for (lbl in names(h2b_map)) {
    r <- get_coef_result(fe_all, "Model 4: L1 Within + Between", h2b_map[[lbl]], "+")
    hyp_results$Estimate[hyp_idx(lbl)]  <- r$est
    hyp_results$p_value[hyp_idx(lbl)]   <- r$p
    hyp_results$Supported[hyp_idx(lbl)] <- ifelse(isTRUE(r$supported), "Yes", "No")
}

# H3a-c: L2 study variables (M5)
h3_map <- list(
    "H3a" = list(term = "br_mean_c",  dir = "+"),
    "H3b" = list(term = "vio_mean_c", dir = "+"),
    "H3c" = list(term = "js_mean_c",  dir = "-")
)
for (lbl in names(h3_map)) {
    r <- get_coef_result(
        fe_all, "Model 5: L1 + L2 Study Variables",
        h3_map[[lbl]]$term, h3_map[[lbl]]$dir
    )
    hyp_results$Estimate[hyp_idx(lbl)]  <- r$est
    hyp_results$p_value[hyp_idx(lbl)]   <- r$p
    hyp_results$Supported[hyp_idx(lbl)] <- ifelse(isTRUE(r$supported), "Yes", "No")
}

# H4a-b main effects (M3)
h4_main_map <- list(
    "H4a:main" = "meetings_count_within",
    "H4b:main" = "meetings_mins_within"
)
for (lbl in names(h4_main_map)) {
    r <- get_coef_result(fe_all, "Model 3: L1 Within-Person", h4_main_map[[lbl]], "+")
    hyp_results$Estimate[hyp_idx(lbl)]  <- r$est
    hyp_results$p_value[hyp_idx(lbl)]   <- r$p
    hyp_results$Supported[hyp_idx(lbl)] <- ifelse(isTRUE(r$supported), "Yes", "No")
}

hyp_results <- hyp_results |>
    dplyr::mutate(p_value = round(p_value, 4))

readr::write_csv(
    hyp_results,
    file.path(FIGS_DIR, "mlm_04_hypothesis_tests.csv")
)
log_msg("  Saved hypothesis tests CSV")

p_hyp_grob <- gridExtra::tableGrob(hyp_results,
    rows = NULL,
    theme = gridExtra::ttheme_minimal(base_size = 9)
)
p_hyp <- ggplot2::ggplot() +
    ggplot2::annotation_custom(p_hyp_grob) +
    ggplot2::theme_void()
save_tbl(p_hyp, "mlm_04_hypothesis_tests.pdf", width = 18, height = 10)
log_msg("  Saved hypothesis tests PDF")


# =============================================================================
# [15] ASSUMPTION DIAGNOSTICS
# =============================================================================
log_msg("=== [15] Assumption diagnostics ===")

check_assumptions(m5_reml, "Model 5")
check_assumptions(m6_reml, "Model 6")

# VIF plots for key models
save_vif_plot(vif_m5, "Model 5", figs_dir = FIGS_DIR)
save_vif_plot(vif_m6, "Model 6", figs_dir = FIGS_DIR)


# =============================================================================
# [16] EFFECT SIZES
# =============================================================================
log_msg("=== [16] Effect sizes ===")

# --- 16a. Standardized coefficients (beta) -----------------------------------
log_msg("  Computing standardized coefficients (method = 'basic')...")

es_models <- list(m3_reml, m5_reml, m6_reml)
es_names <- c(
    "Model 3: L1 Within-Person",
    "Model 5: L1 + L2 Study Variables",
    "Model 6: Full Model with Covariates"
)

std_effects <- purrr::map2_dfr(es_models, es_names, compute_standardized_coefs)
readr::write_csv(
    std_effects,
    file.path(FIGS_DIR, "mlm_05_standardized_effects.csv")
)
log_msg("  Saved standardized effects CSV")

# --- 16b. Level-specific pseudo-d --------------------------------------------
log_msg("  Computing level-specific pseudo-d effect sizes...")

pseudo_d_all <- purrr::map2_dfr(es_models, es_names, compute_level_specific_es)
readr::write_csv(
    pseudo_d_all,
    file.path(FIGS_DIR, "mlm_06_level_specific_es.csv")
)
log_msg("  Saved level-specific effect sizes CSV")

# Log notable effects
notable <- pseudo_d_all |>
    dplyr::filter(
        !term %in% c("(Intercept)", "time_c"),
        !is.na(pseudo_d)
    ) |>
    dplyr::arrange(dplyr::desc(abs(pseudo_d)))

if (nrow(notable) > 0) {
    log_msg("  Top 5 pseudo-d effects (absolute):")
    for (i in seq_len(min(5, nrow(notable)))) {
        log_msg(
            "    ", notable$model[i], " | ", notable$term[i],
            " | d = ", round(notable$pseudo_d[i], 3),
            " (", notable$magnitude[i], ", ", notable$level[i], ")"
        )
    }
}

# --- 16c. Delta-R² and Cohen's f² --------------------------------------------
log_msg("  Computing delta-R2 and Cohen's f2...")

delta_r2_tbl <- compute_delta_r2(comparison_tbl)
readr::write_csv(
    delta_r2_tbl,
    file.path(FIGS_DIR, "mlm_07_delta_r2.csv")
)
log_msg("  Saved delta-R2 / f2 CSV")

for (i in seq_len(nrow(delta_r2_tbl))) {
    log_msg(
        "    ", delta_r2_tbl$Model[i],
        " | dR2m = ", round(delta_r2_tbl$delta_R2_marginal[i], 4),
        " | f2 = ", round(delta_r2_tbl$f2[i], 4),
        " (", delta_r2_tbl$f2_magnitude[i], ")"
    )
}

# --- 16d. Forest plot of pseudo-d (Model 5) ----------------------------------
log_msg("  Generating effect size forest plot...")

# Use Model 5 (substantive model before demographics)
plot_data <- pseudo_d_all |>
    dplyr::filter(
        model == "Model 5: L1 + L2 Study Variables",
        !term %in% c("(Intercept)", "time_c"),
        !is.na(pseudo_d)
    ) |>
    dplyr::mutate(
        term_label = stringr::str_replace_all(term, "_", " ") |>
            stringr::str_to_title(),
        term_label = forcats::fct_reorder(term_label, pseudo_d)
    )


if (nrow(plot_data) > 0) {
    p_forest <- ggplot(plot_data, aes(
        x = pseudo_d, y = term_label,
        color = level
    )) +
        geom_vline(xintercept = 0, linetype = "dashed", color = "grey50") +
        geom_point(size = 2.5) +
        geom_errorbar(
            aes(xmin = pseudo_d_lo, xmax = pseudo_d_hi),
            width = 0.2, orientation = "y"
        ) +
        # Cohen's d benchmarks
        annotate("rect",
            xmin = -0.20, xmax = 0.20,
            ymin = -Inf, ymax = Inf,
            alpha = 0.06, fill = "grey50"
        ) +
        scale_color_manual(values = c(
            "L1 (within)" = "#0072B2",
            "L2 (between)" = "#D55E00"
        )) +
        labs(
            title = "Level-Specific Effect Sizes (Pseudo-d)",
            subtitle = "Model 5: L1 + L2 Study Variables | Shaded band = negligible (|d| < 0.20)",
            x = "Pseudo-d (coefficient / level-appropriate SD of DV)",
            y = NULL,
            color = "Level"
        )
    save_fig(p_forest, "mlm_es_forest_plot.svg",
        width = 11, height = max(6, nrow(plot_data) * 0.4)
    )
}

# --- 16e. R² decomposition stacked bar chart ----------------------------------
log_msg("  Generating R2 decomposition chart...")

r2_plot_data <- comparison_tbl |>
    dplyr::filter(!is.na(R2_marginal)) |>
    dplyr::mutate(
        R2_random_only = R2_conditional - R2_marginal,
        R2_unexplained = 1 - R2_conditional,
        model_short = stringr::str_extract(Model, "Model \\d")
    ) |>
    dplyr::select(
        model_short, R2_marginal, R2_random_only, R2_unexplained
    ) |>
    tidyr::pivot_longer(
        cols = c(R2_marginal, R2_random_only, R2_unexplained),
        names_to = "component",
        values_to = "proportion"
    ) |>
    dplyr::mutate(
        component = factor(component,
            levels = c("R2_unexplained", "R2_random_only", "R2_marginal"),
            labels = c("Unexplained", "Random Effects Only", "Fixed Effects (Marginal)")
        )
    )

p_r2 <- ggplot(r2_plot_data, aes(
    x = model_short, y = proportion,
    fill = component
)) +
    geom_col(width = 0.7) +
    scale_fill_manual(values = c(
        "Fixed Effects (Marginal)" = "#0072B2",
        "Random Effects Only" = "#56B4E9",
        "Unexplained" = "#E0E0E0"
    )) +
    scale_y_continuous(
        labels = scales::percent_format(),
        expand = expansion(mult = c(0, 0.02))
    ) +
    labs(
        title = expression(R^2 ~ "Decomposition Across Model Building Sequence"),
        subtitle = "Nakagawa & Schielzeth (2013) marginal and conditional R-squared",
        x = NULL, y = "Proportion of Variance", fill = NULL
    ) +
    coord_flip()

save_fig(p_r2, "mlm_es_r2_decomposition.svg", width = 10, height = 6)


# =============================================================================
# [17] PHASE 6: L1 x L1 MODERATION (M7a AND M7b)
# =============================================================================
log_msg("=== [17] Phase 6: L1 x L1 Moderation ===")
log_msg("  H4a moderation: Meeting count moderates burnout/NF composite -> TI (WP)")
log_msg("  H4b moderation: Meeting minutes moderates burnout/NF composite -> TI (WP)")
log_msg("  Composites replace facets; within/between decomp retained")

# Product terms (both components already CWC from variable prep)
df$burnout_x_mtgcount <- df$burnout_mean_within * df$meetings_count_within
df$nf_x_mtgcount <- df$nf_mean_within * df$meetings_count_within
df$burnout_x_mtgmins <- df$burnout_mean_within * df$meetings_mins_within
df$nf_x_mtgmins <- df$nf_mean_within * df$meetings_mins_within


# --- [17a] M7a: Meeting Count x Burnout/NF Composites -----------------------
log_msg("=== [17a] Model 7a: Meeting Count x Burnout/NF ===")

m7a_formula <- as.formula(paste(
    "turnover_intention_mean ~ time_c +",
    "burnout_mean_within + nf_mean_within +",
    "meetings_count_within + meetings_mins_within +",
    "burnout_mean_between + nf_mean_between +",
    "meetings_count_between + meetings_mins_between +",
    "pa_mean_c + na_mean_c + br_mean_c + vio_mean_c + js_mean_c +",
    "burnout_mean_within:meetings_count_within +",
    "nf_mean_within:meetings_count_within +",
    re_term
))
log_msg("  Formula: ", deparse(m7a_formula, width.cutoff = 200))

m7a_reml <- safe_lmer(m7a_formula, data = df, REML = TRUE)
m7a_ml <- safe_lmer(m7a_formula, data = df, REML = FALSE)

# Compare M7a against composite-only baseline (M5 re-parameterized)
m7a_base_formula <- as.formula(paste(
    "turnover_intention_mean ~ time_c +",
    "burnout_mean_within + nf_mean_within +",
    "meetings_count_within + meetings_mins_within +",
    "burnout_mean_between + nf_mean_between +",
    "meetings_count_between + meetings_mins_between +",
    "pa_mean_c + na_mean_c + br_mean_c + vio_mean_c + js_mean_c +",
    re_term
))
m7a_base_ml <- safe_lmer(m7a_base_formula, data = df, REML = FALSE)

lrt_7av_base <- compare_models(m7a_base_ml, m7a_ml, "M7a base", "Model 7a")
log_msg(
    "  LRT M7a vs composite base: chi2 = ", round(lrt_7av_base$chi_sq, 3),
    ", df = ", lrt_7av_base$df,
    ", p = ", format.pval(lrt_7av_base$p_value, digits = 4)
)

fe7a <- broom.mixed::tidy(m7a_reml, effects = "fixed", conf.int = TRUE)

# H4a: burnout x meeting count
row_burn_cnt <- fe7a[fe7a$term == "burnout_mean_within:meetings_count_within", ]
if (nrow(row_burn_cnt) > 0) {
    log_msg(
        "  H4a:burn burnout x mtgcount: b = ", round(row_burn_cnt$estimate, 4),
        ", p = ", format.pval(row_burn_cnt$p.value, digits = 4),
        " -> ", ifelse(row_burn_cnt$p.value < 0.05, "SIGNIFICANT", "ns")
    )
}

# H4a: nf x meeting count
row_nf_cnt <- fe7a[fe7a$term == "nf_mean_within:meetings_count_within", ]
if (nrow(row_nf_cnt) > 0) {
    log_msg(
        "  H4a:nf NF x mtgcount: b = ", round(row_nf_cnt$estimate, 4),
        ", p = ", format.pval(row_nf_cnt$p.value, digits = 4),
        " -> ", ifelse(row_nf_cnt$p.value < 0.05, "SIGNIFICANT", "ns")
    )
}

# Simple slopes if significant (burnout x count)
m7a_plots <- list()
if (!is.null(m7a_reml) && nrow(row_burn_cnt) > 0 && row_burn_cnt$p.value < 0.05) {
    log_msg("  Probing H4a:burn interaction (burnout x meeting count)...")
    ss_burn_cnt <- tryCatch(
        interactions::sim_slopes(m7a_reml,
            pred = burnout_mean_within,
            modx = meetings_count_within,
            jnplot = FALSE
        ),
        error = function(e) {
            log_msg("  [WARN] sim_slopes failed: ", conditionMessage(e))
            NULL
        }
    )
    if (!is.null(ss_burn_cnt)) {
        p_int <- interactions::interact_plot(m7a_reml,
            pred = burnout_mean_within,
            modx = meetings_count_within,
            interval = TRUE
        ) +
            labs(
                title = "H4a: Meeting Count x Within-Person Burnout",
                subtitle = "Simple slopes at ±1 SD of meeting count",
                x = "Within-Person Burnout (CWC)", y = "Turnover Intention"
            )
        m7a_plots[["burnout_count"]] <- p_int
    }
}

# Simple slopes if significant (NF x count)
if (!is.null(m7a_reml) && nrow(row_nf_cnt) > 0 && row_nf_cnt$p.value < 0.05) {
    log_msg("  Probing H4a:nf interaction (NF x meeting count)...")
    p_int_nf <- tryCatch(
        interactions::interact_plot(m7a_reml,
            pred = nf_mean_within,
            modx = meetings_count_within,
            interval = TRUE
        ) +
            labs(
                title = "H4a: Meeting Count x Within-Person NF",
                subtitle = "Simple slopes at ±1 SD of meeting count",
                x = "Within-Person NF (CWC)", y = "Turnover Intention"
            ),
        error = function(e) NULL
    )
    if (!is.null(p_int_nf)) m7a_plots[["nf_count"]] <- p_int_nf
}

if (length(m7a_plots) > 0) {
    p_m7a_combined <- patchwork::wrap_plots(m7a_plots, ncol = 1)
    save_fig(p_m7a_combined, "mlm_m7a_interaction.svg",
        width = 10, height = 5 * length(m7a_plots)
    )
}

m7a_summary <- extract_model_summary(m7a_reml, "Model 7a: Count x Composites")


# --- [17b] M7b: Meeting Minutes x Burnout/NF Composites ---------------------
log_msg("=== [17b] Model 7b: Meeting Minutes x Burnout/NF ===")

m7b_formula <- as.formula(paste(
    "turnover_intention_mean ~ time_c +",
    "burnout_mean_within + nf_mean_within +",
    "meetings_count_within + meetings_mins_within +",
    "burnout_mean_between + nf_mean_between +",
    "meetings_count_between + meetings_mins_between +",
    "pa_mean_c + na_mean_c + br_mean_c + vio_mean_c + js_mean_c +",
    "burnout_mean_within:meetings_mins_within +",
    "nf_mean_within:meetings_mins_within +",
    re_term
))
log_msg("  Formula: ", deparse(m7b_formula, width.cutoff = 200))

m7b_reml <- safe_lmer(m7b_formula, data = df, REML = TRUE)
m7b_ml <- safe_lmer(m7b_formula, data = df, REML = FALSE)

lrt_7bv_base <- compare_models(m7a_base_ml, m7b_ml, "M7b base", "Model 7b")
log_msg(
    "  LRT M7b vs composite base: chi2 = ", round(lrt_7bv_base$chi_sq, 3),
    ", df = ", lrt_7bv_base$df,
    ", p = ", format.pval(lrt_7bv_base$p_value, digits = 4)
)

fe7b <- broom.mixed::tidy(m7b_reml, effects = "fixed", conf.int = TRUE)

row_burn_min <- fe7b[fe7b$term == "burnout_mean_within:meetings_mins_within", ]
if (nrow(row_burn_min) > 0) {
    log_msg(
        "  H4b:burn burnout x mtgmins: b = ", round(row_burn_min$estimate, 4),
        ", p = ", format.pval(row_burn_min$p.value, digits = 4),
        " -> ", ifelse(row_burn_min$p.value < 0.05, "SIGNIFICANT", "ns")
    )
}

row_nf_min <- fe7b[fe7b$term == "nf_mean_within:meetings_mins_within", ]
if (nrow(row_nf_min) > 0) {
    log_msg(
        "  H4b:nf NF x mtgmins: b = ", round(row_nf_min$estimate, 4),
        ", p = ", format.pval(row_nf_min$p.value, digits = 4),
        " -> ", ifelse(row_nf_min$p.value < 0.05, "SIGNIFICANT", "ns")
    )
}

m7b_plots <- list()
if (!is.null(m7b_reml) && nrow(row_burn_min) > 0 && row_burn_min$p.value < 0.05) {
    log_msg("  Probing H4b:burn interaction (burnout x meeting minutes)...")
    p_int_bm <- tryCatch(
        interactions::interact_plot(m7b_reml,
            pred = burnout_mean_within,
            modx = meetings_mins_within,
            interval = TRUE
        ) +
            labs(
                title = "H4b: Meeting Minutes x Within-Person Burnout",
                subtitle = "Simple slopes at ±1 SD of meeting minutes",
                x = "Within-Person Burnout (CWC)", y = "Turnover Intention"
            ),
        error = function(e) NULL
    )
    if (!is.null(p_int_bm)) m7b_plots[["burnout_mins"]] <- p_int_bm
}

if (!is.null(m7b_reml) && nrow(row_nf_min) > 0 && row_nf_min$p.value < 0.05) {
    log_msg("  Probing H4b:nf interaction (NF x meeting minutes)...")
    p_int_nm <- tryCatch(
        interactions::interact_plot(m7b_reml,
            pred = nf_mean_within,
            modx = meetings_mins_within,
            interval = TRUE
        ) +
            labs(
                title = "H4b: Meeting Minutes x Within-Person NF",
                subtitle = "Simple slopes at ±1 SD of meeting minutes",
                x = "Within-Person NF (CWC)", y = "Turnover Intention"
            ),
        error = function(e) NULL
    )
    if (!is.null(p_int_nm)) m7b_plots[["nf_mins"]] <- p_int_nm
}

if (length(m7b_plots) > 0) {
    p_m7b_combined <- patchwork::wrap_plots(m7b_plots, ncol = 1)
    save_fig(p_m7b_combined, "mlm_m7b_interaction.svg",
        width = 10, height = 5 * length(m7b_plots)
    )
}

m7b_summary <- extract_model_summary(m7b_reml, "Model 7b: Minutes x Composites")

# =============================================================================
# [17c] PHASE 7: ICC-BETA (rho_beta) — SLOPE HETEROGENEITY
# =============================================================================
log_msg("=== [17c] Phase 7: ICC-beta (rho_beta) slope heterogeneity ===")
log_msg("  Aguinis & Culpepper (2015): proportion of WP variance from slope diffs")
log_msg("  8 predictors: 6 facet-level (CWC) + 2 composite-level (CWC)")

vy <- var(df$turnover_intention_mean, na.rm = TRUE)

rho_beta_predictors <- c(
    "pf_mean_within", "cw_mean_within", "ee_mean_within",
    "comp_mean_within", "auto_mean_within", "relt_mean_within",
    "burnout_mean_within", "nf_mean_within"
)

iccb_results <- purrr::map_dfr(rho_beta_predictors, function(pred) {
    log_msg("  Computing rho_beta for: ", pred)

    # Try correlated random effects first
    f1 <- as.formula(paste(
        "turnover_intention_mean ~", pred, "+ (", pred, "| response_id)"
    ))
    fit <- tryCatch(
        safe_lmer(f1, data = df, REML = FALSE),
        error = function(e) NULL
    )
    status <- "correlated"

    # Fallback: uncorrelated
    if (is.null(fit) || isSingular(fit)) {
        f2 <- as.formula(paste(
            "turnover_intention_mean ~", pred, "+ (", pred, "|| response_id)"
        ))
        fit <- tryCatch(
            safe_lmer(f2, data = df, REML = FALSE),
            error = function(e) NULL
        )
        status <- "uncorrelated"
    }

    # Singular / failed — record zero
    if (is.null(fit) || isSingular(fit)) {
        log_msg("  [WARN] Model singular for: ", pred, " -> rho_beta = 0")
        return(data.frame(
            predictor = pred,
            rho_beta = 0,
            tau11 = 0,
            model_status = "singular",
            stringsAsFactors = FALSE
        ))
    }

    # Compute rho_beta
    rb <- tryCatch(
        {
            X <- model.matrix(fit)
            p <- ncol(X)
            T1 <- as.matrix(VarCorr(fit)$response_id)[1:p, 1:p, drop = FALSE]
            iccbeta::icc_beta(X, df[["response_id"]], T1, vy)$rho_beta
        },
        error = function(e) {
            log_msg("  [WARN] icc_beta failed for ", pred, ": ", conditionMessage(e))
            NA_real_
        }
    )

    # Extract tau11 (random slope variance)
    vc <- as.data.frame(VarCorr(fit))
    tau11_val <- vc$vcov[
        vc$grp == "response_id" & vc$var1 == pred & is.na(vc$var2)
    ]
    if (length(tau11_val) == 0) tau11_val <- 0

    log_msg("  rho_beta = ", round(rb, 4), " | tau11 = ", round(tau11_val, 4))

    data.frame(
        predictor = pred,
        rho_beta = rb,
        tau11 = tau11_val,
        model_status = status,
        stringsAsFactors = FALSE
    )
})

# Magnitude benchmark (LeBreton & Senter, 2008 as cited in Aguinis & Culpepper)
iccb_results <- iccb_results |>
    dplyr::mutate(
        magnitude = dplyr::case_when(
            is.na(rho_beta) ~ NA_character_,
            rho_beta < 0.01 ~ "negligible (<.01)",
            rho_beta < 0.05 ~ "small-medium (.01-.05)",
            rho_beta < 0.10 ~ "medium (.05-.10)",
            TRUE ~ "large (>.10)"
        )
    )

readr::write_csv(iccb_results, file.path(FIGS_DIR, "mlm_08_iccbeta.csv"))
log_msg("  Saved rho_beta CSV")

# Print summary
log_msg("  rho_beta results:")
for (i in seq_len(nrow(iccb_results))) {
    log_msg(
        "    ", iccb_results$predictor[i],
        " | rho_beta = ", round(iccb_results$rho_beta[i], 4),
        " (", iccb_results$magnitude[i], ")",
        " | status: ", iccb_results$model_status[i]
    )
}

# ICC-alpha for reference
icc_alpha <- performance::icc(m0_reml)$ICC_adjusted
log_msg(
    "  rho_alpha (ICC from M0) = ", round(icc_alpha, 4),
    " | Orthogonal to rho_beta"
)

# Visualization: horizontal bar chart with magnitude bands
p_iccbeta <- iccb_results |>
    dplyr::filter(!is.na(rho_beta)) |>
    dplyr::mutate(
        predictor = dplyr::recode(predictor,
            pf_mean_within      = "PF (within)",
            cw_mean_within      = "CW (within)",
            ee_mean_within      = "EE (within)",
            comp_mean_within    = "Comp (within)",
            auto_mean_within    = "Auto (within)",
            relt_mean_within    = "Relt (within)",
            burnout_mean_within = "Burnout composite (within)",
            nf_mean_within      = "NF composite (within)"
        ),
        predictor = forcats::fct_reorder(predictor, rho_beta),
        magnitude = factor(magnitude, levels = c(
            "negligible (<.01)", "small-medium (.01-.05)",
            "medium (.05-.10)", "large (>.10)"
        ))
    ) |>
    ggplot2::ggplot(ggplot2::aes(x = rho_beta, y = predictor, fill = magnitude)) +
    ggplot2::geom_col() +
    ggplot2::geom_vline(
        xintercept = c(0.01, 0.05, 0.10),
        linetype = "dashed", color = "grey40", linewidth = 0.4
    ) +
    ggplot2::annotate("text",
        x = c(0.01, 0.05, 0.10), y = 0.5,
        label = c(".01", ".05", ".10"),
        size = 3, color = "grey40", vjust = -0.3
    ) +
    ggplot2::scale_fill_manual(
        values = c(
            "negligible (<.01)" = "#E0E0E0",
            "small-medium (.01-.05)" = "#56B4E9",
            "medium (.05-.10)" = "#0072B2",
            "large (>.10)" = "#D55E00"
        ),
        drop = FALSE
    ) +
    ggplot2::labs(
        title = expression(rho[beta] ~ "Slope Heterogeneity by L1 Predictor"),
        subtitle = paste0(
            "Aguinis & Culpepper (2015) | rho_alpha = ",
            round(icc_alpha, 3),
            " | Reference lines: .01 / .05 / .10"
        ),
        x = expression(rho[beta]),
        y = NULL,
        fill = "Magnitude"
    )

save_fig(p_iccbeta, "mlm_08_iccbeta.svg", width = 10, height = 6)
log_msg("  Saved rho_beta bar chart SVG")


# =============================================================================
# [17b] PHASE 6 POST-FIT: SUMMARY COMPLETIONS (M7a, M7b)
# =============================================================================
log_msg("=== [17b] Phase 6 post-fit completions ===")

phase6_names <- c(
    "Model 7a: Count x Composites",
    "Model 7b: Minutes x Composites"
)
phase6_fits_reml <- list(m7a_reml, m7b_reml)

# Phase 6 model comparison table (supplements mlm_01)
phase6_tbl <- purrr::map2_dfr(
    phase6_fits_reml, phase6_names,
    function(fit, name) {
        if (is.null(fit)) return(tibble::tibble(Model = name))
        gl <- broom.mixed::glance(fit)
        r2 <- tryCatch(
            performance::r2_nakagawa(fit),
            error = function(e) list(R2_marginal = NA, R2_conditional = NA)
        )
        vc <- as.data.frame(VarCorr(fit))
        tau_00_val <- vc$vcov[
            vc$grp == "response_id" &
                vc$var1 == "(Intercept)" & is.na(vc$var2)
        ]
        if (length(tau_00_val) == 0) tau_00_val <- NA
        sigma2_val <- vc$vcov[vc$grp == "Residual"]
        if (length(sigma2_val) == 0) sigma2_val <- NA
        tibble::tibble(
            Model = name, AIC = gl$AIC, BIC = gl$BIC,
            logLik = gl$logLik,
            deviance = if ("deviance" %in% names(gl)) gl$deviance else NA_real_,
            n_fixed = length(fixef(fit)),
            R2_marginal = r2$R2_marginal, R2_conditional = r2$R2_conditional,
            tau_00 = tau_00_val, sigma2 = sigma2_val
        )
    }
)

phase6_lrt <- dplyr::bind_rows(
    lrt_7av_base |> dplyr::transmute(
        Model = phase6_names[1],
        LRT_chi2 = chi_sq, LRT_df = df, LRT_p = p_value
    ),
    lrt_7bv_base |> dplyr::transmute(
        Model = phase6_names[2],
        LRT_chi2 = chi_sq, LRT_df = df, LRT_p = p_value
    )
)
phase6_tbl <- dplyr::left_join(phase6_tbl, phase6_lrt, by = "Model")
readr::write_csv(phase6_tbl, file.path(FIGS_DIR, "mlm_01b_phase6_comparison.csv"))
log_msg("  Saved Phase 6 model comparison CSV (M7a, M7b vs composite base)")

# Append M7a/M7b to fixed effects table and re-save
fe_phase6_all <- purrr::map2_dfr(
    phase6_fits_reml, phase6_names,
    function(fit, name) {
        if (is.null(fit)) return(tibble::tibble(model = name))
        broom.mixed::tidy(fit, effects = "fixed", conf.int = TRUE) |>
            dplyr::mutate(model = name)
    }
)
fe_all <- dplyr::bind_rows(fe_all, fe_phase6_all)
readr::write_csv(fe_all, file.path(FIGS_DIR, "mlm_02_fixed_effects.csv"))
log_msg("  Updated fixed effects CSV with M7a/M7b rows")

# Complete H4a-b moderation rows in hypothesis table
fe7a_tbl <- broom.mixed::tidy(m7a_reml, effects = "fixed", conf.int = TRUE) |>
    dplyr::mutate(model = "Model 7a: Count x Composites")
fe7b_tbl <- broom.mixed::tidy(m7b_reml, effects = "fixed", conf.int = TRUE) |>
    dplyr::mutate(model = "Model 7b: Minutes x Composites")
fe_phase6 <- dplyr::bind_rows(fe7a_tbl, fe7b_tbl)

h4_mod_map <- list(
    "H4a:burn" = list(model = "Model 7a: Count x Composites",
                      term  = "burnout_mean_within:meetings_count_within"),
    "H4a:nf"   = list(model = "Model 7a: Count x Composites",
                      term  = "nf_mean_within:meetings_count_within"),
    "H4b:burn" = list(model = "Model 7b: Minutes x Composites",
                      term  = "burnout_mean_within:meetings_mins_within"),
    "H4b:nf"   = list(model = "Model 7b: Minutes x Composites",
                      term  = "nf_mean_within:meetings_mins_within")
)
for (lbl in names(h4_mod_map)) {
    r_row <- fe_phase6 |>
        dplyr::filter(
            model == h4_mod_map[[lbl]]$model,
            term  == h4_mod_map[[lbl]]$term
        )
    if (nrow(r_row) > 0) {
        hyp_results$Estimate[hyp_idx(lbl)]  <- round(r_row$estimate[1], 4)
        hyp_results$p_value[hyp_idx(lbl)]   <- r_row$p.value[1]
        hyp_results$Supported[hyp_idx(lbl)] <- ifelse(
            r_row$p.value[1] < 0.05, "Yes", "No"
        )
    }
}
hyp_results <- hyp_results |> dplyr::mutate(p_value = round(p_value, 4))
readr::write_csv(hyp_results, file.path(FIGS_DIR, "mlm_04_hypothesis_tests.csv"))
log_msg("  Updated hypothesis tests CSV with H4 moderation results")

# Assumption diagnostics for M7a/M7b
check_assumptions(m7a_reml, "Model 7a")
check_assumptions(m7b_reml, "Model 7b")
save_vif_plot(check_vif(m7a_reml, "Model 7a"), "Model 7a", figs_dir = FIGS_DIR)
save_vif_plot(check_vif(m7b_reml, "Model 7b"), "Model 7b", figs_dir = FIGS_DIR)

# Effect sizes for M7a/M7b (append to existing CSVs)
es_m7_models <- list(m7a_reml, m7b_reml)
es_m7_names  <- phase6_names

std_effects_m7 <- purrr::map2_dfr(es_m7_models, es_m7_names, compute_standardized_coefs)
std_effects_all <- dplyr::bind_rows(std_effects, std_effects_m7)
readr::write_csv(std_effects_all, file.path(FIGS_DIR, "mlm_05_standardized_effects.csv"))
log_msg("  Updated standardized effects CSV with M7a/M7b")

pseudo_d_m7 <- purrr::map2_dfr(es_m7_models, es_m7_names, compute_level_specific_es)
pseudo_d_all_final <- dplyr::bind_rows(pseudo_d_all, pseudo_d_m7)
readr::write_csv(pseudo_d_all_final, file.path(FIGS_DIR, "mlm_06_level_specific_es.csv"))
log_msg("  Updated level-specific effect sizes CSV with M7a/M7b")


# =============================================================================
# [18] SESSION SUMMARY
# =============================================================================
log_msg("=== [18] Session Summary ===")

csv_files <- list.files(FIGS_DIR, pattern = "\\.csv$")
svg_files <- list.files(FIGS_DIR, pattern = "\\.svg$")
pdf_files <- list.files(FIGS_DIR, pattern = "\\.pdf$")
log_msg("Output directory: ", FIGS_DIR)
log_msg("CSV files generated: ", length(csv_files))
log_msg("SVG files generated: ", length(svg_files))
log_msg("PDF files generated: ", length(pdf_files))
log_msg("")
log_msg("Random effects decision: ", re_note)
log_msg("Hypotheses tested: H1a-b (WP facets), H2a-b (BP facet means), H3a-c (L2 vars), H4a-b (meetings)")
log_msg("Phases 1-2 (M0-M2): variance partitioning and time trend baselines")
log_msg("Phase 2 (M3): WP facet effects (H1a, H1b, H4a-b main)")
log_msg("Phase 3 (M4): BP facet mean effects (H2a, H2b)")
log_msg("Phase 4 (M5): L2 study variables (H3a-c)")
log_msg("Phase 5 (M6): demographic sensitivity — data-driven covariate selection")
log_msg("Phase 6 (M7a-b): L1xL1 moderation with composites (H4a-b)")
log_msg("Phase 7: rho_beta for 8 predictors (6 facets + 2 composites)")
log_msg("")
log_msg("=== MULTILEVEL MODEL BUILDING COMPLETE ===")

cat("\n=== Session Info ===\n")
sessionInfo()
