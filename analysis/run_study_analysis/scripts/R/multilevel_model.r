#!/usr/bin/env Rscript
# =============================================================================
# analysis/run_study_analysis/scripts/R/multilevel_model.r
#
# Multilevel Model Building Sequence for Turnover Intentions
# Following dissertation proposal (Curran & Bauer 2011; Enders & Tofighi 2007)
#
# Design: N = 322 participants (L2) x 3 within-day timepoints (L1)
# DV    : turnover_intention_mean (1-5 ordinal, treated as continuous)
# Output: CSVs + SVGs -> analysis/run_study_analysis/figs/mlm/
#
# Hypotheses (aligned to proposal-final-draft.txt):
#   H1a  : WP NF facets (comp, auto, relt) -> TI (+)                  [M3]
#   H1b  : BP NF facet means -> TI (+)                                 [M4]
#   H2a  : WP burnout facets (pf, cw, ee) -> TI (+)                   [M3]
#   H2b  : BP burnout facet means -> TI (+)                            [M4]
#   H3a  : WP meeting load x NF composite -> TI (moderation)          [M7a/M7b]
#   H3b  : WP meeting load x burnout composite -> TI (moderation)      [M7a/M7b]
#   H4a  : BP PC breach -> TI (+)                                      [M5]
#   H4b  : BP PC violation -> TI (+)                                   [M5]
#   H5   : BP job satisfaction -> TI (-)                               [M5]
#
# Phase 1 (M0-M2): Variance partitioning and time trend baselines
# Phase 2 (M3)  : WP main effects -- L1 facets (H2a, H1a, meeting mains)
#                 + recruitment_source (mandatory per manuscript)
# Phase 3 (M4)  : BP mean components of L1 variables (H2b, H1b)
# Phase 4 (M5)  : L2 study variables: breach, violation, JS (H4a, H4b, H5)
# Phase 5 (M6)  : Demographic sensitivity (data-driven covariate selection)
# Phase 6 (M7a-b): L1 x L1 moderation -- meetings x burnout/NF (H3a, H3b)
# Phase 7       : ICC-beta (rho_beta) slope heterogeneity
#
# Centering: Enders & Tofighi (2007) / Curran & Bauer (2011) -- see prep_mlm.r
#   - L1 predictors: person-mean centered (within) + grand-mean centered
#     person means (between) via datawizard::demean()
#   - L2 predictors: grand-mean centered (_c suffix)
#   - ATCB: CWC-decomposed but excluded from all MLM formulas (CFA marker only)
#   - Composites: burnout_mean, nf_mean CWC-decomposed for M7a/M7b
#
# recruitment_source: Per manuscript, entered as mandatory L2 covariate in all
#   primary models (M3+). Dummy-coded (cloudresearch as reference level).
#   Controls for systematic between-sample differences while preserving full
#   sample for within-person effect estimation.
#
# meetings_time: Duration in minutes from supplement backfill; NAs where
#   neither survey nor supplement provided a value. Rows with NA on any model
#   term are excluded via lmer's default na.action = na.omit.
#
# Estimation:
#   - ML  for likelihood ratio tests (model comparison)
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

source(here::here("analysis", "shared", "utils", "common_utils.r"))
source(here::here("analysis", "shared", "utils", "plot_utils.r"))
source(here::here("analysis", "shared", "utils", "mlm_utils.r"))

source(here::here("analysis", "run_study_analysis", "utils", "data_loader.r"))
source(here::here("analysis", "run_study_analysis", "utils", "prep_mlm.r"))
source(here::here("analysis", "run_study_analysis", "utils", "mlm_hypothesis_map.r"))
source(here::here("analysis", "run_synthetic_data", "utils", "mlm_diagnostics.r"))

FIGS_DIR <- here::here("analysis", "run_study_analysis", "figs", "mlm")
ensure_dir(FIGS_DIR)

theme_set(theme_apa)

save_fig <- make_save_fig(FIGS_DIR)
save_tbl <- make_save_tbl(FIGS_DIR)

CTRL <- lmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 200000))

log_msg("=== MULTILEVEL MODEL BUILDING SEQUENCE ===")
log_msg("Output directory: ", FIGS_DIR)


# =============================================================================
# [1] DATA LOADING AND PREPARATION
# =============================================================================
log_msg("=== [1] Loading and preparing data ===")

df_raw <- load_cleaned_data()

n_participants <- dplyr::n_distinct(df_raw$response_id)
log_msg("Participants (L2): ", n_participants)
log_msg("Timepoints  (L1) : ", max(df_raw$timepoint))

# Variable group definitions from canonical data_loader.r
l1_predictor_vars <- VARIABLE_DEFS$l1_predictor_vars
l1_marker_var <- VARIABLE_DEFS$l1_marker_var
l2_study_vars <- VARIABLE_DEFS$l2_study_vars
l2_control_vars <- VARIABLE_DEFS$l2_control_vars
l2_demo_vars <- VARIABLE_DEFS$l2_demo_vars
dv <- VARIABLE_DEFS$dv

# Pretty labels for output tables
var_labels <- c(
    pf_mean = "Physical Fatigue", cw_mean = "Cognitive Weariness",
    ee_mean = "Emotional Exhaustion", comp_mean = "NF: Competence",
    auto_mean = "NF: Autonomy", relt_mean = "NF: Relatedness",
    atcb_mean = "ATCB (Marker)",
    meetings_count = "Meeting Count", meetings_time = "Meeting Time (min)",
    pa_mean = "Positive Affect", na_mean = "Negative Affect",
    br_mean = "PC Breach", vio_mean = "PC Violation",
    js_mean = "Job Satisfaction",
    jis_mean = "Job Insecurity (JIS)", des_mean = "Desirability of Movement (DES)",
    turnover_intention_mean = "Turnover Intention"
)


# =============================================================================
# [2] CENTERING AND VARIABLE PREPARATION (sourced from prep_mlm.r)
# =============================================================================
log_msg("=== [2] Centering and variable preparation ===")

df <- prepare_mlm_frame(df_raw, VARIABLE_DEFS)

log_msg("  Total rows after preparation: ", nrow(df))
log_msg("  Total columns: ", ncol(df))
log_msg("  recruitment_source distribution:")
tbl_rs <- table(df$recruitment_source[!duplicated(df$response_id)])
for (nm in names(tbl_rs)) {
    log_msg("    ", nm, ": ", tbl_rs[nm])
}


# =============================================================================
# [3] HELPER NOTE
# =============================================================================
# All modeling helpers (safe_lmer, extract_model_summary, compare_models,
# check_vif, save_vif_plot, compute_standardized_coefs,
# compute_level_specific_es, compute_delta_r2, verify_centering,
# select_covariates_bivariate) sourced from analysis/shared/utils/mlm_utils.r.
# check_assumptions() sourced from run_synthetic_data/utils/mlm_diagnostics.r.
# HYPOTHESIS_MAP, get_coef_result(), evaluate_hypotheses() sourced from
# run_study_analysis/utils/mlm_hypothesis_map.r.
# =============================================================================


# =============================================================================
# [4] MODEL 0: UNCONDITIONAL MEANS (EMPTY/NULL)
# =============================================================================
log_msg("=== [4] Model 0: Unconditional Means ===")
log_msg("  Design prerequisite: ICC justifies MLM (> 0.05 threshold)")

m0_reml <- safe_lmer(turnover_intention_mean ~ 1 + (1 | response_id),
    data = df, REML = TRUE
)
m0_ml <- safe_lmer(turnover_intention_mean ~ 1 + (1 | response_id),
    data = df, REML = FALSE
)

icc_m0 <- performance::icc(m0_reml)
log_msg("  ICC (adjusted)    = ", round(icc_m0$ICC_adjusted, 4))
log_msg("  ICC (conditional) = ", round(icc_m0$ICC_conditional, 4))

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
# [5] MODEL 1: UNCONDITIONAL GROWTH -- FIXED TIME
# =============================================================================
log_msg("=== [5] Model 1: Unconditional Growth (Fixed Slope) ===")

m1_reml <- safe_lmer(turnover_intention_mean ~ time_c + (1 | response_id),
    data = df, REML = TRUE
)
m1_ml <- safe_lmer(turnover_intention_mean ~ time_c + (1 | response_id),
    data = df, REML = FALSE
)

lrt_1v0 <- compare_models(m0_ml, m1_ml, "Model 0", "Model 1")
log_msg(
    "  LRT Model 1 vs 0: chi2 = ", round(lrt_1v0$chi_sq, 3),
    ", df = ", lrt_1v0$df, ", p = ", format.pval(lrt_1v0$p_value, digits = 4)
)

time_coef <- fixef(m1_reml)["time_c"]
log_msg("  time_c coefficient = ", round(time_coef, 4))
log_msg(
    "  Baseline time trend: time_c = ", round(time_coef, 4),
    " -> ", ifelse(
        time_coef > 0 && lrt_1v0$p_value < 0.05,
        "POSITIVE (p < .05)",
        "not significant or negative"
    )
)

m1_summary <- extract_model_summary(m1_reml, "Model 1: Fixed Time")


# =============================================================================
# [6] MODEL 2: UNCONDITIONAL GROWTH -- RANDOM SLOPE
# =============================================================================
log_msg("=== [6] Model 2: Unconditional Growth (Random Slope) ===")
log_msg("  3-timepoint design: ICC-beta replaces formal significance test for slopes")

m2_reml <- safe_lmer(
    turnover_intention_mean ~ time_c + (time_c | response_id),
    data = df, REML = TRUE
)
m2_ml <- safe_lmer(
    turnover_intention_mean ~ time_c + (time_c | response_id),
    data = df, REML = FALSE
)

use_random_slope <- TRUE
re_note <- "correlated"

if (is.null(m2_reml) || isSingular(m2_reml)) {
    log_msg("  [INFO] Full random slope singular. Trying uncorrelated (time_c || response_id)...")
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
    log_msg("  [INFO] Random slope not supported. Proceeding with random intercept only.")
    use_random_slope <- FALSE
    re_note <- "intercept only"
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

    vc_m2 <- as.data.frame(VarCorr(m2_reml))
    tau_11_val <- vc_m2$vcov[
        vc_m2$grp == "response_id" & vc_m2$var1 == "time_c" & is.na(vc_m2$var2)
    ]
    tau_11 <- if (length(tau_11_val) > 0) tau_11_val[1] else NA
    log_msg("  Random slope variance (tau_11) = ", ifelse(is.na(tau_11), "NA", round(tau_11, 4)))

    if (!is.na(lrt_2v1$p_value) && lrt_2v1$p_value >= 0.05) {
        log_msg("  [INFO] Random slope LRT ns (p >= .05); retaining random intercept only.")
        use_random_slope <- FALSE
        re_note <- "intercept only (LRT ns)"
    }
} else {
    lrt_2v1 <- tibble::tibble(
        comparison = "Model 2 vs Model 1",
        chi_sq = NA_real_, df = NA_integer_, p_value = NA_real_
    )
    log_msg("  Random slope not estimable with 3 timepoints; retained random intercept only.")
}

m2_summary <- extract_model_summary(m2_reml, "Model 2: Random Slope")
log_msg("  Decision: use_random_slope = ", use_random_slope, " (", re_note, ")")


# =============================================================================
# [7] MODEL 3: WITHIN-PERSON (L1) PREDICTORS + recruitment_source
# =============================================================================
log_msg("=== [7] Model 3: Within-Person (L1) Predictors ===")
log_msg("  Tests H2a (WP burnout facets), H1a (WP NF facets), meeting main effects")
log_msg("  recruitment_source: mandatory L2 control (manuscript: all primary models)")

re_term <- if (use_random_slope) "(time_c | response_id)" else "(1 | response_id)"

m3_formula <- as.formula(paste(
    "turnover_intention_mean ~ time_c +",
    "pf_mean_within + cw_mean_within + ee_mean_within +",
    "comp_mean_within + auto_mean_within + relt_mean_within +",
    "meetings_count_within + meetings_time_within +",
    "recruitment_source +",
    re_term
))
log_msg("  Formula: ", deparse(m3_formula, width.cutoff = 200))

m3_reml <- safe_lmer(m3_formula, data = df, REML = TRUE)
m3_ml <- safe_lmer(m3_formula, data = df, REML = FALSE)

m_prev_ml <- if (use_random_slope) m2_ml else m1_ml
prev_name <- if (use_random_slope) "Model 2" else "Model 1"
lrt_3vp <- compare_models(m_prev_ml, m3_ml, prev_name, "Model 3")
log_msg(
    "  LRT Model 3 vs ", prev_name, ": chi2 = ",
    round(lrt_3vp$chi_sq, 3),
    ", df = ", lrt_3vp$df, ", p = ", format.pval(lrt_3vp$p_value, digits = 4)
)

fe3 <- broom.mixed::tidy(m3_reml, effects = "fixed", conf.int = TRUE)

h3_vars <- c(
    "pf_mean_within", "cw_mean_within", "ee_mean_within",
    "comp_mean_within", "auto_mean_within", "relt_mean_within",
    "meetings_count_within", "meetings_time_within"
)
h3_labels <- c(
    "H2a:pf", "H2a:cw", "H2a:ee",
    "H1a:comp", "H1a:auto", "H1a:relt",
    "meetings_count:main", "meetings_time:main"
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

vif_m3 <- check_vif(m3_reml, "Model 3")
m3_summary <- extract_model_summary(m3_reml, "Model 3: L1 Within-Person")


# =============================================================================
# [8] MODEL 4: ADD BETWEEN-PERSON COMPONENTS OF L1 VARIABLES
# =============================================================================
log_msg("=== [8] Model 4: Between-Person Components of L1 Variables ===")
log_msg("  Tests H2b (BP burnout facet means -> TI), H1b (BP NF facet means -> TI)")

m4_formula <- as.formula(paste(
    "turnover_intention_mean ~ time_c +",
    "pf_mean_within + cw_mean_within + ee_mean_within +",
    "comp_mean_within + auto_mean_within + relt_mean_within +",
    "meetings_count_within + meetings_time_within +",
    "pf_mean_between + cw_mean_between + ee_mean_between +",
    "comp_mean_between + auto_mean_between + relt_mean_between +",
    "meetings_count_between + meetings_time_between +",
    "recruitment_source +",
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

fe4 <- broom.mixed::tidy(m4_reml, effects = "fixed", conf.int = TRUE)

for (v in l1_predictor_vars) {
    wp_row <- fe4[fe4$term == paste0(v, "_within"), ]
    bp_row <- fe4[fe4$term == paste0(v, "_between"), ]
    if (nrow(wp_row) > 0 && nrow(bp_row) > 0) {
        ctx <- bp_row$estimate - wp_row$estimate
        log_msg("  Contextual effect (", v, "): BP - WP = ", round(ctx, 4))
    }
}

h2b_vars <- c("pf_mean_between", "cw_mean_between", "ee_mean_between")
h2b_labels <- c("H2b:pf", "H2b:cw", "H2b:ee")
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

h1b_vars <- c("comp_mean_between", "auto_mean_between", "relt_mean_between")
h1b_labels <- c("H1b:comp", "H1b:auto", "H1b:relt")
for (i in seq_along(h1b_vars)) {
    row <- fe4[fe4$term == h1b_vars[i], ]
    if (nrow(row) > 0) {
        log_msg(
            "  ", h1b_labels[i], " (", h1b_vars[i], "): b = ",
            round(row$estimate, 4), ", p = ",
            format.pval(row$p.value, digits = 4),
            " -> ", ifelse(row$estimate > 0 & row$p.value < 0.05,
                "SUPPORTED", "NOT SUPPORTED"
            )
        )
    }
}

vif_m4 <- check_vif(m4_reml, "Model 4")
m4_summary <- extract_model_summary(m4_reml, "Model 4: L1 Within + Between")


# =============================================================================
# [9] MODEL 5: ADD L2 STUDY VARIABLES
# =============================================================================
log_msg("=== [9] Model 5: L2 Between-Person Study Variables ===")
log_msg("  Tests H4a (breach -> TI), H4b (violation -> TI), H5 (JS -> TI)")
log_msg("  PA/NA entered as affect controls; JIS/DES as mandatory environmental controls")

m5_formula <- as.formula(paste(
    "turnover_intention_mean ~ time_c +",
    "pf_mean_within + cw_mean_within + ee_mean_within +",
    "comp_mean_within + auto_mean_within + relt_mean_within +",
    "meetings_count_within + meetings_time_within +",
    "pf_mean_between + cw_mean_between + ee_mean_between +",
    "comp_mean_between + auto_mean_between + relt_mean_between +",
    "meetings_count_between + meetings_time_between +",
    "pa_mean_c + na_mean_c + jis_mean_c + des_mean_c +",
    "br_mean_c + vio_mean_c + js_mean_c +",
    "recruitment_source +",
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

fe5 <- broom.mixed::tidy(m5_reml, effects = "fixed", conf.int = TRUE)

for (ctrl in c("pa_mean_c", "na_mean_c", "jis_mean_c", "des_mean_c")) {
    row <- fe5[fe5$term == ctrl, ]
    if (nrow(row) > 0) {
        dir <- switch(ctrl,
            pa_mean_c  = "negative",
            na_mean_c  = "positive",
            jis_mean_c = "positive",
            des_mean_c = "positive"
        )
        log_msg(
            "  Control (", ctrl, "): b = ", round(row$estimate, 4),
            ", p = ", format.pval(row$p.value, digits = 4),
            " (expected: ", dir, ")"
        )
    }
}

h5_vars <- c("br_mean_c", "vio_mean_c", "js_mean_c")
h5_labels <- c("H4a", "H4b", "H5")
h5_directions <- c("positive", "positive", "negative")
for (i in seq_along(h5_vars)) {
    row <- fe5[fe5$term == h5_vars[i], ]
    if (nrow(row) > 0) {
        expected <- if (h5_directions[i] == "positive") {
            row$estimate > 0
        } else {
            row$estimate < 0
        }
        log_msg(
            "  ", h5_labels[i], " (", h5_vars[i], "): b = ",
            round(row$estimate, 4), ", p = ",
            format.pval(row$p.value, digits = 4),
            " (expected: ", h5_directions[i], ")",
            " -> ", ifelse(expected & row$p.value < 0.05,
                "SUPPORTED", "NOT SUPPORTED"
            )
        )
    }
}

vif_m5 <- check_vif(m5_reml, "Model 5")
m5_summary <- extract_model_summary(m5_reml, "Model 5: L1 + L2 Study Variables")


# =============================================================================
# [10] MODEL 6: DEMOGRAPHIC COVARIATES -- DATA-DRIVEN SELECTION
# =============================================================================
log_msg("=== [10] Model 6: Demographic Covariates (data-driven selection) ===")
log_msg("  Mandatory controls (theory-justified): age_c, job_tenure")
log_msg("  Screened via Bernerth & Aguinis (2016): is_remote")
log_msg("  recruitment_source already in M3-M5; retained in M6")
log_msg("  PA/NA, JIS, DES already in M5 as controls; not re-screened here")

mandatory_covs <- c("age_c", "job_tenure")
screened_candidates <- c("is_remote")

df_bp <- df |>
    dplyr::group_by(response_id) |>
    dplyr::summarise(
        ti_mean = mean(turnover_intention_mean, na.rm = TRUE),
        age_c = dplyr::first(age_c),
        gender = dplyr::first(gender),
        job_tenure = dplyr::first(job_tenure),
        is_remote = dplyr::first(is_remote),
        edu_lvl = dplyr::first(edu_lvl),
        ethnicity = dplyr::first(ethnicity),
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
log_msg(
    "  Selected covariates (|r| >= .10): ",
    if (length(cov_screen$selected) > 0) paste(cov_screen$selected, collapse = ", ") else "none"
)

readr::write_csv(cov_screen$cor_table, file.path(FIGS_DIR, "mlm_09_covariate_screening.csv"))
log_msg("  Saved covariate screening CSV")

m5_base_terms <- paste(
    "turnover_intention_mean ~ time_c +",
    "pf_mean_within + cw_mean_within + ee_mean_within +",
    "comp_mean_within + auto_mean_within + relt_mean_within +",
    "meetings_count_within + meetings_time_within +",
    "pf_mean_between + cw_mean_between + ee_mean_between +",
    "comp_mean_between + auto_mean_between + relt_mean_between +",
    "meetings_count_between + meetings_time_between +",
    "pa_mean_c + na_mean_c + jis_mean_c + des_mean_c +",
    "br_mean_c + vio_mean_c + js_mean_c +",
    "recruitment_source"
)

all_m6_covs <- c(mandatory_covs, cov_screen$selected)
log_msg("  Mandatory covariates: ", paste(mandatory_covs, collapse = ", "))
log_msg(
    "  Screened covariates added (|r| >= .10): ",
    if (length(cov_screen$selected) > 0) paste(cov_screen$selected, collapse = ", ") else "none"
)

cov_terms <- paste(all_m6_covs, collapse = " + ")
m6_formula <- as.formula(paste(m5_base_terms, "+", cov_terms, "+", re_term))
log_msg("  Formula: ", deparse(m6_formula, width.cutoff = 200))

m6_reml <- safe_lmer(m6_formula, data = df, REML = TRUE)
m6_ml <- safe_lmer(m6_formula, data = df, REML = FALSE)

lrt_6v5 <- compare_models(m5_ml, m6_ml, "Model 5", "Model 6")
log_msg(
    "  LRT Model 6 vs 5: chi2 = ", round(lrt_6v5$chi_sq, 3),
    ", df = ", lrt_6v5$df, ", p = ", format.pval(lrt_6v5$p_value, digits = 4)
)

fe6 <- broom.mixed::tidy(m6_reml, effects = "fixed", conf.int = TRUE)

log_msg("  Checking stability of substantive effects (Model 5 -> 6):")
check_stability_vars <- c(
    h3_vars, paste0(l1_predictor_vars, "_between"), h5_vars,
    "jis_mean_c", "des_mean_c"
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
m6_summary <- extract_model_summary(m6_reml, "Model 6: Full Model with Covariates")


# =============================================================================
# [11] MODEL COMPARISON TABLE (M0-M6)
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
model_fits_reml <- list(m0_reml, m1_reml, m2_reml, m3_reml, m4_reml, m5_reml, m6_reml)
model_fits_ml <- list(m0_ml, m1_ml, m2_ml, m3_ml, m4_ml, m5_ml, m6_ml)

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

lrt_all <- dplyr::bind_rows(
    tibble::tibble(Model = model_names[1], LRT_chi2 = NA, LRT_df = NA, LRT_p = NA),
    lrt_1v0 |> dplyr::transmute(Model = model_names[2], LRT_chi2 = chi_sq, LRT_df = df, LRT_p = p_value),
    lrt_2v1 |> dplyr::transmute(Model = model_names[3], LRT_chi2 = chi_sq, LRT_df = df, LRT_p = p_value),
    lrt_3vp |> dplyr::transmute(Model = model_names[4], LRT_chi2 = chi_sq, LRT_df = df, LRT_p = p_value),
    lrt_4v3 |> dplyr::transmute(Model = model_names[5], LRT_chi2 = chi_sq, LRT_df = df, LRT_p = p_value),
    lrt_5v4 |> dplyr::transmute(Model = model_names[6], LRT_chi2 = chi_sq, LRT_df = df, LRT_p = p_value),
    lrt_6v5 |> dplyr::transmute(Model = model_names[7], LRT_chi2 = chi_sq, LRT_df = df, LRT_p = p_value)
)

comparison_tbl <- dplyr::left_join(comparison_tbl, lrt_all, by = "Model")
readr::write_csv(comparison_tbl, file.path(FIGS_DIR, "mlm_01_model_comparison.csv"))
log_msg("  Saved model comparison CSV")

comparison_display <- comparison_tbl |> dplyr::mutate(across(where(is.numeric), ~ round(., 3)))
p_comp_grob <- gridExtra::tableGrob(comparison_display,
    rows = NULL,
    theme = gridExtra::ttheme_minimal(base_size = 8)
)
p_comp <- ggplot2::ggplot() +
    ggplot2::annotation_custom(p_comp_grob) +
    ggplot2::theme_void()
save_tbl(p_comp, "mlm_01_model_comparison.pdf", width = 18, height = 6)
save_md(comparison_display, file.path(FIGS_DIR, "mlm_01_model_comparison.md"))


# =============================================================================
# [12] FIXED EFFECTS SUMMARY TABLE
# =============================================================================
log_msg("=== [12] Building fixed effects summary ===")

fe_all <- purrr::map2_dfr(model_fits_reml, model_names, function(fit, name) {
    if (is.null(fit)) {
        return(tibble::tibble(model = name))
    }
    broom.mixed::tidy(fit, effects = "fixed", conf.int = TRUE, conf.level = 0.95) |>
        dplyr::mutate(model = name)
})

readr::write_csv(fe_all, file.path(FIGS_DIR, "mlm_02_fixed_effects.csv"))
log_msg("  Saved fixed effects CSV")

for (i in seq_along(model_names)) {
    sub_tbl <- fe_all |>
        dplyr::filter(model == model_names[i]) |>
        dplyr::select(term, estimate, std.error, statistic, df, p.value, conf.low, conf.high) |>
        dplyr::mutate(
            across(c(estimate, std.error, statistic, conf.low, conf.high), ~ round(., 4)),
            df = round(df, 1),
            p.value = dplyr::case_when(
                is.na(p.value) ~ NA_character_,
                p.value < .001 ~ "< .001",
                TRUE ~ as.character(round(p.value, 4))
            )
        )

    grob <- gridExtra::tableGrob(sub_tbl,
        rows = NULL,
        theme = gridExtra::ttheme_minimal(base_size = 9)
    )
    p_sub <- ggplot2::ggplot() +
        ggplot2::annotation_custom(grob) +
        ggplot2::labs(title = model_names[i]) +
        ggplot2::theme_void() +
        ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", size = 12, hjust = 0.5))
    fn_base <- paste0("mlm_02_fixed_effects_", gsub("[^a-z0-9]+", "_", tolower(model_names[i])))
    save_tbl(p_sub, paste0(fn_base, ".pdf"), width = 14, height = max(4, nrow(sub_tbl) * 0.4))
    save_md(sub_tbl, file.path(FIGS_DIR, paste0(fn_base, ".md")))
}

save_md(
    fe_all |> dplyr::mutate(
        across(c(estimate, std.error, statistic, conf.low, conf.high), ~ round(., 4)),
        df = round(df, 1),
        p.value = dplyr::case_when(
            is.na(p.value) ~ NA_character_,
            p.value < .001 ~ "< .001",
            TRUE ~ as.character(round(p.value, 4))
        )
    ),
    file.path(FIGS_DIR, "mlm_02_fixed_effects.md")
)
log_msg("  Saved fixed effects PDFs and markdown")


# =============================================================================
# [13] RANDOM EFFECTS SUMMARY TABLE
# =============================================================================
log_msg("=== [13] Building random effects summary ===")

re_all <- purrr::map2_dfr(model_fits_reml, model_names, function(fit, name) {
    if (is.null(fit)) {
        return(tibble::tibble(model = name))
    }
    broom.mixed::tidy(fit, effects = "ran_pars") |> dplyr::mutate(model = name)
})

readr::write_csv(re_all, file.path(FIGS_DIR, "mlm_03_random_effects.csv"))
log_msg("  Saved random effects CSV")

re_display <- re_all |> dplyr::mutate(across(where(is.numeric), ~ round(., 4)))
re_grob <- gridExtra::tableGrob(re_display,
    rows = NULL,
    theme = gridExtra::ttheme_minimal(base_size = 9)
)
p_re <- ggplot2::ggplot() +
    ggplot2::annotation_custom(re_grob) +
    ggplot2::theme_void()
save_tbl(p_re, "mlm_03_random_effects.pdf", width = 12, height = 8)
save_md(re_display, file.path(FIGS_DIR, "mlm_03_random_effects.md"))


# =============================================================================
# [14] HYPOTHESIS TESTING SUMMARY (M0-M6 portion; H3 completed after M7)
# =============================================================================
log_msg("=== [14] Building hypothesis testing summary ===")

hyp_results <- evaluate_hypotheses(
    fe_all    = fe_all,
    hyp_map   = HYPOTHESIS_MAP,
    icc_value = icc_m0$ICC_adjusted
)

hyp_results <- hyp_results |> dplyr::mutate(p_value = round(p_value, 4))

readr::write_csv(hyp_results, file.path(FIGS_DIR, "mlm_04_hypothesis_tests.csv"))
log_msg("  Saved hypothesis tests CSV (moderation rows pending Phase 6)")

p_hyp_grob <- gridExtra::tableGrob(hyp_results,
    rows = NULL,
    theme = gridExtra::ttheme_minimal(base_size = 9)
)
p_hyp <- ggplot2::ggplot() +
    ggplot2::annotation_custom(p_hyp_grob) +
    ggplot2::theme_void()
save_tbl(p_hyp, "mlm_04_hypothesis_tests.pdf", width = 18, height = 10)
save_md(hyp_results, file.path(FIGS_DIR, "mlm_04_hypothesis_tests.md"))


# =============================================================================
# [15] ASSUMPTION DIAGNOSTICS (M5 and M6)
# =============================================================================
log_msg("=== [15] Assumption diagnostics ===")

check_assumptions(m5_reml, "Model 5", FIGS_DIR)
check_assumptions(m6_reml, "Model 6", FIGS_DIR)
save_vif_plot(vif_m5, "Model 5", figs_dir = FIGS_DIR)
save_vif_plot(vif_m6, "Model 6", figs_dir = FIGS_DIR)


# =============================================================================
# [16] EFFECT SIZES (M3-M6)
# =============================================================================
log_msg("=== [16] Effect sizes ===")

es_models <- list(m3_reml, m4_reml, m5_reml, m6_reml)
es_names <- c(
    "Model 3: L1 Within-Person",
    "Model 4: L1 Within + Between",
    "Model 5: L1 + L2 Study Variables",
    "Model 6: Full Model with Covariates"
)

log_msg("  Computing standardized coefficients (method = 'basic')...")
std_effects <- purrr::map2_dfr(es_models, es_names, compute_standardized_coefs)
readr::write_csv(std_effects, file.path(FIGS_DIR, "mlm_05_standardized_effects.csv"))
log_msg("  Saved standardized effects CSV")

log_msg("  Computing level-specific pseudo-d effect sizes...")
pseudo_d_all <- purrr::map2_dfr(es_models, es_names, compute_level_specific_es)
readr::write_csv(pseudo_d_all, file.path(FIGS_DIR, "mlm_06_level_specific_es.csv"))
log_msg("  Saved level-specific effect sizes CSV")

notable <- pseudo_d_all |>
    dplyr::filter(!term %in% c("(Intercept)", "time_c"), !is.na(pseudo_d)) |>
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

log_msg("  Computing delta-R2 and Cohen's f2...")
delta_r2_tbl <- compute_delta_r2(comparison_tbl)
readr::write_csv(delta_r2_tbl, file.path(FIGS_DIR, "mlm_07_delta_r2.csv"))
log_msg("  Saved delta-R2 / f2 CSV")

for (i in seq_len(nrow(delta_r2_tbl))) {
    log_msg(
        "    ", delta_r2_tbl$Model[i],
        " | dR2m = ", round(delta_r2_tbl$delta_R2_marginal[i], 4),
        " | f2 = ", round(delta_r2_tbl$f2[i], 4),
        " (", delta_r2_tbl$f2_magnitude[i], ")"
    )
}

# Forest plot (Model 5)
plot_data <- pseudo_d_all |>
    dplyr::filter(
        model == "Model 5: L1 + L2 Study Variables",
        !term %in% c("(Intercept)", "time_c"),
        !is.na(pseudo_d)
    ) |>
    dplyr::mutate(
        term_label = stringr::str_replace_all(term, "_", " ") |> stringr::str_to_title(),
        term_label = forcats::fct_reorder(term_label, pseudo_d)
    )

if (nrow(plot_data) > 0) {
    p_forest <- ggplot(plot_data, aes(x = pseudo_d, y = term_label, color = level)) +
        geom_vline(xintercept = 0, linetype = "dashed", color = "grey50") +
        geom_point(size = 2.5) +
        geom_errorbar(aes(xmin = pseudo_d_lo, xmax = pseudo_d_hi), width = 0.2) +
        annotate("rect",
            xmin = -0.20, xmax = 0.20, ymin = -Inf, ymax = Inf,
            alpha = 0.06, fill = "grey50"
        ) +
        scale_color_manual(values = c(
            "L1 (within)" = "#0072B2",
            "L2 (between)" = "#D55E00"
        )) +
        labs(
            title = "Level-Specific Effect Sizes (Pseudo-d)",
            subtitle = "Model 5: L1 + L2 Study Variables | Shaded band = negligible (|d| < 0.20)",
            x = "Pseudo-d", y = NULL, color = "Level"
        )
    save_fig(p_forest, "mlm_es_forest_plot.svg", width = 11, height = max(6, nrow(plot_data) * 0.4))
}

# R2 decomposition
r2_plot_data <- comparison_tbl |>
    dplyr::filter(!is.na(R2_marginal)) |>
    dplyr::mutate(
        R2_random_only = R2_conditional - R2_marginal,
        R2_unexplained = 1 - R2_conditional,
        model_short    = stringr::str_extract(Model, "Model \\d")
    ) |>
    dplyr::select(model_short, R2_marginal, R2_random_only, R2_unexplained) |>
    tidyr::pivot_longer(
        cols = c(R2_marginal, R2_random_only, R2_unexplained),
        names_to = "component", values_to = "proportion"
    ) |>
    dplyr::mutate(
        component = factor(component,
            levels = c("R2_unexplained", "R2_random_only", "R2_marginal"),
            labels = c("Unexplained", "Random Effects Only", "Fixed Effects (Marginal)")
        )
    )

p_r2 <- ggplot(r2_plot_data, aes(x = model_short, y = proportion, fill = component)) +
    geom_col(width = 0.7) +
    scale_fill_manual(values = c(
        "Fixed Effects (Marginal)" = "#0072B2",
        "Random Effects Only"      = "#56B4E9",
        "Unexplained"              = "#E0E0E0"
    )) +
    scale_y_continuous(labels = scales::percent_format(), expand = expansion(mult = c(0, 0.02))) +
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
log_msg("  H3a: Meeting load moderates NF composite -> TI (WP)")
log_msg("  H3b: Meeting load moderates burnout composite -> TI (WP)")
log_msg("  Two meeting-load indicators: meetings_count (count) and meetings_time (minutes)")
log_msg("  Composites: burnout_mean_within (pf+cw+ee) and nf_mean_within (comp+auto+relt)")
#
# COVARIATE NOTE: M7a/M7b include recruitment_source (mandatory per manuscript)
# but omit the bivariate-screened demographic covariates from M6. Switching to
# composites already reduces model complexity; adding M6's screened set would
# over-parameterize the moderation test given 3 timepoints per person.
#
# OPERATIONALIZATION: Meeting load is operationalized as two indicators (count
# and time in minutes), yielding four interaction tests in two models. Both
# must be significant for full support of H3a or H3b.


# --- [17a] M7a: Meeting Count x Burnout/NF Composites -----------------------
log_msg("=== [17a] Model 7a: Meeting Count x Burnout/NF ===")

m7a_formula <- as.formula(paste(
    "turnover_intention_mean ~ time_c +",
    "burnout_mean_within + nf_mean_within +",
    "meetings_count_within + meetings_time_within +",
    "burnout_mean_between + nf_mean_between +",
    "meetings_count_between + meetings_time_between +",
    "pa_mean_c + na_mean_c + jis_mean_c + des_mean_c +",
    "br_mean_c + vio_mean_c + js_mean_c +",
    "recruitment_source +",
    "burnout_mean_within:meetings_count_within +",
    "nf_mean_within:meetings_count_within +",
    re_term
))
log_msg("  Formula: ", deparse(m7a_formula, width.cutoff = 200))

m7a_reml <- safe_lmer(m7a_formula, data = df, REML = TRUE)
m7a_ml <- safe_lmer(m7a_formula, data = df, REML = FALSE)

m7a_base_formula <- as.formula(paste(
    "turnover_intention_mean ~ time_c +",
    "burnout_mean_within + nf_mean_within +",
    "meetings_count_within + meetings_time_within +",
    "burnout_mean_between + nf_mean_between +",
    "meetings_count_between + meetings_time_between +",
    "pa_mean_c + na_mean_c + jis_mean_c + des_mean_c +",
    "br_mean_c + vio_mean_c + js_mean_c +",
    "recruitment_source +",
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

row_burn_cnt <- fe7a[fe7a$term == "burnout_mean_within:meetings_count_within", ]
if (nrow(row_burn_cnt) > 0) {
    log_msg(
        "  H3b:count burnout x mtgcount: b = ", round(row_burn_cnt$estimate, 4),
        ", p = ", format.pval(row_burn_cnt$p.value, digits = 4),
        " -> ", ifelse(row_burn_cnt$p.value < 0.05, "SIGNIFICANT", "ns")
    )
}

row_nf_cnt <- fe7a[fe7a$term == "nf_mean_within:meetings_count_within", ]
if (nrow(row_nf_cnt) > 0) {
    log_msg(
        "  H3a:count NF x mtgcount: b = ", round(row_nf_cnt$estimate, 4),
        ", p = ", format.pval(row_nf_cnt$p.value, digits = 4),
        " -> ", ifelse(row_nf_cnt$p.value < 0.05, "SIGNIFICANT", "ns")
    )
}

m7a_plots <- list()
if (!is.null(m7a_reml) && nrow(row_burn_cnt) > 0 && row_burn_cnt$p.value < 0.05) {
    log_msg("  Probing H3b:count (burnout x meeting count)...")
    ss_burn_cnt <- tryCatch(
        interactions::sim_slopes(m7a_reml,
            pred = burnout_mean_within, modx = meetings_count_within, jnplot = FALSE
        ),
        error = function(e) {
            log_msg("  [WARN] sim_slopes failed: ", conditionMessage(e))
            NULL
        }
    )
    if (!is.null(ss_burn_cnt)) {
        p_int <- interactions::interact_plot(m7a_reml,
            pred = burnout_mean_within, modx = meetings_count_within, interval = TRUE
        ) + labs(
            title = "H3b: Meeting Count x Within-Person Burnout",
            subtitle = "Simple slopes at +/-1 SD of meeting count",
            x = "Within-Person Burnout (CWC)", y = "Turnover Intention"
        )
        m7a_plots[["burnout_count"]] <- p_int
    }
}

if (!is.null(m7a_reml) && nrow(row_nf_cnt) > 0 && row_nf_cnt$p.value < 0.05) {
    log_msg("  Probing H3a:count (NF x meeting count)...")
    p_int_nf <- tryCatch(
        interactions::interact_plot(m7a_reml,
            pred = nf_mean_within, modx = meetings_count_within, interval = TRUE
        ) + labs(
            title = "H3a: Meeting Count x Within-Person NF",
            subtitle = "Simple slopes at +/-1 SD of meeting count",
            x = "Within-Person NF (CWC)", y = "Turnover Intention"
        ),
        error = function(e) NULL
    )
    if (!is.null(p_int_nf)) m7a_plots[["nf_count"]] <- p_int_nf
}

if (length(m7a_plots) > 0) {
    p_m7a <- patchwork::wrap_plots(m7a_plots, ncol = 1)
    save_fig(p_m7a, "mlm_m7a_interaction.svg", width = 10, height = 5 * length(m7a_plots))
}

m7a_summary <- extract_model_summary(m7a_reml, "Model 7a: Count x Composites")


# --- [17b] M7b: Meeting Time x Burnout/NF Composites ------------------------
log_msg("=== [17b] Model 7b: Meeting Time x Burnout/NF ===")

m7b_formula <- as.formula(paste(
    "turnover_intention_mean ~ time_c +",
    "burnout_mean_within + nf_mean_within +",
    "meetings_count_within + meetings_time_within +",
    "burnout_mean_between + nf_mean_between +",
    "meetings_count_between + meetings_time_between +",
    "pa_mean_c + na_mean_c + jis_mean_c + des_mean_c +",
    "br_mean_c + vio_mean_c + js_mean_c +",
    "recruitment_source +",
    "burnout_mean_within:meetings_time_within +",
    "nf_mean_within:meetings_time_within +",
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

row_burn_time <- fe7b[fe7b$term == "burnout_mean_within:meetings_time_within", ]
if (nrow(row_burn_time) > 0) {
    log_msg(
        "  H3b:time burnout x mtgtime: b = ", round(row_burn_time$estimate, 4),
        ", p = ", format.pval(row_burn_time$p.value, digits = 4),
        " -> ", ifelse(row_burn_time$p.value < 0.05, "SIGNIFICANT", "ns")
    )
}

row_nf_time <- fe7b[fe7b$term == "nf_mean_within:meetings_time_within", ]
if (nrow(row_nf_time) > 0) {
    log_msg(
        "  H3a:time NF x mtgtime: b = ", round(row_nf_time$estimate, 4),
        ", p = ", format.pval(row_nf_time$p.value, digits = 4),
        " -> ", ifelse(row_nf_time$p.value < 0.05, "SIGNIFICANT", "ns")
    )
}

m7b_plots <- list()
if (!is.null(m7b_reml) && nrow(row_burn_time) > 0 && row_burn_time$p.value < 0.05) {
    log_msg("  Probing H3b:time (burnout x meeting time)...")
    p_int_bm <- tryCatch(
        interactions::interact_plot(m7b_reml,
            pred = burnout_mean_within, modx = meetings_time_within, interval = TRUE
        ) + labs(
            title = "H3b: Meeting Time x Within-Person Burnout",
            subtitle = "Simple slopes at +/-1 SD of meeting time",
            x = "Within-Person Burnout (CWC)", y = "Turnover Intention"
        ),
        error = function(e) NULL
    )
    if (!is.null(p_int_bm)) m7b_plots[["burnout_time"]] <- p_int_bm
}

if (!is.null(m7b_reml) && nrow(row_nf_time) > 0 && row_nf_time$p.value < 0.05) {
    log_msg("  Probing H3a:time (NF x meeting time)...")
    p_int_nm <- tryCatch(
        interactions::interact_plot(m7b_reml,
            pred = nf_mean_within, modx = meetings_time_within, interval = TRUE
        ) + labs(
            title = "H3a: Meeting Time x Within-Person NF",
            subtitle = "Simple slopes at +/-1 SD of meeting time",
            x = "Within-Person NF (CWC)", y = "Turnover Intention"
        ),
        error = function(e) NULL
    )
    if (!is.null(p_int_nm)) m7b_plots[["nf_time"]] <- p_int_nm
}

if (length(m7b_plots) > 0) {
    p_m7b <- patchwork::wrap_plots(m7b_plots, ncol = 1)
    save_fig(p_m7b, "mlm_m7b_interaction.svg", width = 10, height = 5 * length(m7b_plots))
}

m7b_summary <- extract_model_summary(m7b_reml, "Model 7b: Time x Composites")

m7_fits_reml <- list(m7a_reml, m7b_reml)
m7_names <- c("Model 7a: Count x Composites", "Model 7b: Time x Composites")

fe_m7 <- purrr::map2_dfr(m7_fits_reml, m7_names, function(fit, name) {
    if (is.null(fit)) {
        return(tibble::tibble(model = name))
    }
    broom.mixed::tidy(fit, effects = "fixed", conf.int = TRUE) |>
        dplyr::mutate(model = name)
})

for (i in seq_along(m7_names)) {
    sub_tbl <- fe_m7 |>
        dplyr::filter(model == m7_names[i]) |>
        dplyr::select(term, estimate, std.error, statistic, df, p.value, conf.low, conf.high) |>
        dplyr::mutate(
            across(c(estimate, std.error, statistic, conf.low, conf.high), ~ round(., 4)),
            df = round(df, 1),
            p.value = dplyr::case_when(
                is.na(p.value) ~ NA_character_,
                p.value < .001 ~ "< .001",
                TRUE ~ as.character(round(p.value, 4))
            )
        )
    grob <- gridExtra::tableGrob(sub_tbl,
        rows = NULL,
        theme = gridExtra::ttheme_minimal(base_size = 9)
    )
    p_sub <- ggplot2::ggplot() +
        ggplot2::annotation_custom(grob) +
        ggplot2::labs(title = m7_names[i]) +
        ggplot2::theme_void() +
        ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", size = 12, hjust = 0.5))
    fn_base <- paste0("mlm_02_fixed_effects_", gsub("[^a-z0-9]+", "_", tolower(m7_names[i])))
    save_tbl(p_sub, paste0(fn_base, ".pdf"), width = 14, height = max(4, nrow(sub_tbl) * 0.4))
    save_md(sub_tbl, file.path(FIGS_DIR, paste0(fn_base, ".md")))
}
log_msg("  Saved M7a/M7b fixed effects PDFs and markdown")


# =============================================================================
# [17c] PHASE 7: ICC-BETA (rho_beta) -- SLOPE HETEROGENEITY
# =============================================================================
log_msg("=== [17c] Phase 7: ICC-beta (rho_beta) slope heterogeneity ===")
log_msg("  Aguinis & Culpepper (2015): proportion of WP variance from slope diffs")

vy <- var(df$turnover_intention_mean, na.rm = TRUE)

rho_beta_predictors <- c(
    "pf_mean_within", "cw_mean_within", "ee_mean_within",
    "comp_mean_within", "auto_mean_within", "relt_mean_within",
    "burnout_mean_within", "nf_mean_within"
)

iccb_results <- purrr::map_dfr(rho_beta_predictors, function(pred) {
    log_msg("  Computing rho_beta for: ", pred)

    f1 <- as.formula(paste("turnover_intention_mean ~", pred, "+ (", pred, "| response_id)"))
    fit <- tryCatch(safe_lmer(f1, data = df, REML = FALSE), error = function(e) NULL)
    status <- "correlated"

    if (is.null(fit) || isSingular(fit)) {
        f2 <- as.formula(paste("turnover_intention_mean ~", pred, "+ (", pred, "|| response_id)"))
        fit <- tryCatch(safe_lmer(f2, data = df, REML = FALSE), error = function(e) NULL)
        status <- "uncorrelated"
    }

    if (is.null(fit) || isSingular(fit)) {
        log_msg("  [WARN] Model singular for: ", pred, " -> rho_beta = 0")
        return(data.frame(
            predictor = pred, rho_beta = 0, tau11 = 0,
            model_status = "singular", stringsAsFactors = FALSE
        ))
    }

    rb <- tryCatch(
        {
            X <- model.matrix(fit)
            p <- ncol(X)
            T1 <- as.matrix(VarCorr(fit)$response_id)[1:p, 1:p, drop = FALSE]
            grp <- as.integer(factor(df[["response_id"]]))
            iccbeta::icc_beta(X, grp, T1, vy)$rho_beta
        },
        error = function(e) {
            log_msg("  [WARN] icc_beta failed for ", pred, ": ", conditionMessage(e))
            NA_real_
        }
    )

    vc <- as.data.frame(VarCorr(fit))
    tau11_val <- vc$vcov[vc$grp == "response_id" & vc$var1 == pred & is.na(vc$var2)]
    if (length(tau11_val) == 0) tau11_val <- 0
    log_msg("  rho_beta = ", round(rb, 4), " | tau11 = ", round(tau11_val, 4))

    data.frame(
        predictor = pred, rho_beta = rb, tau11 = tau11_val,
        model_status = status, stringsAsFactors = FALSE
    )
})

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

for (i in seq_len(nrow(iccb_results))) {
    log_msg(
        "    ", iccb_results$predictor[i],
        " | rho_beta = ", round(iccb_results$rho_beta[i], 4),
        " (", iccb_results$magnitude[i], ")",
        " | status: ", iccb_results$model_status[i]
    )
}

icc_alpha <- performance::icc(m0_reml)$ICC_adjusted
log_msg("  rho_alpha (ICC from M0) = ", round(icc_alpha, 4))

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
            round(icc_alpha, 3), " | Reference lines: .01 / .05 / .10"
        ),
        x = expression(rho[beta]), y = NULL, fill = "Magnitude"
    )
save_fig(p_iccbeta, "mlm_08_iccbeta.svg", width = 10, height = 6)
log_msg("  Saved rho_beta bar chart SVG")


# =============================================================================
# [17d] PHASE 6 POST-FIT: COMPLETE SUMMARY WITH M7a/M7b
# =============================================================================
log_msg("=== [17d] Phase 6 post-fit completions ===")

phase6_names <- c("Model 7a: Count x Composites", "Model 7b: Time x Composites")
phase6_fits_reml <- list(m7a_reml, m7b_reml)

phase6_tbl <- purrr::map2_dfr(phase6_fits_reml, phase6_names, function(fit, name) {
    if (is.null(fit)) {
        return(tibble::tibble(Model = name))
    }
    gl <- broom.mixed::glance(fit)
    r2 <- tryCatch(performance::r2_nakagawa(fit),
        error = function(e) list(R2_marginal = NA, R2_conditional = NA)
    )
    vc <- as.data.frame(VarCorr(fit))
    tau_00_val <- vc$vcov[vc$grp == "response_id" & vc$var1 == "(Intercept)" & is.na(vc$var2)]
    if (length(tau_00_val) == 0) tau_00_val <- NA
    sigma2_val <- vc$vcov[vc$grp == "Residual"]
    if (length(sigma2_val) == 0) sigma2_val <- NA
    tibble::tibble(
        Model = name, AIC = gl$AIC, BIC = gl$BIC, logLik = gl$logLik,
        deviance = if ("deviance" %in% names(gl)) gl$deviance else NA_real_,
        n_fixed = length(fixef(fit)),
        R2_marginal = r2$R2_marginal, R2_conditional = r2$R2_conditional,
        tau_00 = tau_00_val, sigma2 = sigma2_val
    )
})

phase6_lrt <- dplyr::bind_rows(
    lrt_7av_base |> dplyr::transmute(
        Model = phase6_names[1], LRT_chi2 = chi_sq, LRT_df = df, LRT_p = p_value
    ),
    lrt_7bv_base |> dplyr::transmute(
        Model = phase6_names[2], LRT_chi2 = chi_sq, LRT_df = df, LRT_p = p_value
    )
)
phase6_tbl <- dplyr::left_join(phase6_tbl, phase6_lrt, by = "Model")
readr::write_csv(phase6_tbl, file.path(FIGS_DIR, "mlm_01b_phase6_comparison.csv"))
log_msg("  Saved Phase 6 model comparison CSV")

# Append M7a/M7b to fixed effects table
fe_phase6_all <- purrr::map2_dfr(phase6_fits_reml, phase6_names, function(fit, name) {
    if (is.null(fit)) {
        return(tibble::tibble(model = name))
    }
    broom.mixed::tidy(fit, effects = "fixed", conf.int = TRUE) |> dplyr::mutate(model = name)
})
fe_all <- dplyr::bind_rows(fe_all, fe_phase6_all)
readr::write_csv(fe_all, file.path(FIGS_DIR, "mlm_02_fixed_effects.csv"))
log_msg("  Updated fixed effects CSV with M7a/M7b")

re_phase6 <- purrr::map2_dfr(phase6_fits_reml, phase6_names, function(fit, name) {
    if (is.null(fit)) {
        return(tibble::tibble(model = name))
    }
    broom.mixed::tidy(fit, effects = "ran_pars") |> dplyr::mutate(model = name)
})
re_all <- dplyr::bind_rows(re_all, re_phase6)
readr::write_csv(re_all, file.path(FIGS_DIR, "mlm_03_random_effects.csv"))
log_msg("  Updated random effects CSV with M7a/M7b")

# Complete H3a/H3b moderation rows
hyp_mod_rows <- HYPOTHESIS_MAP |> dplyr::filter(stringr::str_starts(hypothesis, "H3"))
hyp_results <- hyp_results |>
    dplyr::rows_update(
        evaluate_hypotheses(
            fe_all    = fe_all,
            hyp_map   = hyp_mod_rows,
            icc_value = icc_m0$ICC_adjusted
        ),
        by = "hypothesis"
    )

hyp_results <- hyp_results |> dplyr::mutate(p_value = round(p_value, 4))
readr::write_csv(hyp_results, file.path(FIGS_DIR, "mlm_04_hypothesis_tests.csv"))

p_hyp_final_grob <- gridExtra::tableGrob(hyp_results,
    rows = NULL,
    theme = gridExtra::ttheme_minimal(base_size = 9)
)
p_hyp_final <- ggplot2::ggplot() +
    ggplot2::annotation_custom(p_hyp_final_grob) +
    ggplot2::theme_void()
save_tbl(p_hyp_final, "mlm_04_hypothesis_tests.pdf", width = 18, height = 10)
save_md(hyp_results, file.path(FIGS_DIR, "mlm_04_hypothesis_tests.md"))
log_msg("  Regenerated hypothesis markdown and PDF with H3a/H3b moderation results")

# Diagnostics and effect sizes for M7a/M7b
check_assumptions(m7a_reml, "Model 7a", FIGS_DIR)
check_assumptions(m7b_reml, "Model 7b", FIGS_DIR)
save_vif_plot(check_vif(m7a_reml, "Model 7a"), "Model 7a", figs_dir = FIGS_DIR)
save_vif_plot(check_vif(m7b_reml, "Model 7b"), "Model 7b", figs_dir = FIGS_DIR)

std_effects_m7 <- purrr::map2_dfr(phase6_fits_reml, phase6_names, compute_standardized_coefs)
std_effects_all <- dplyr::bind_rows(std_effects, std_effects_m7)
readr::write_csv(std_effects_all, file.path(FIGS_DIR, "mlm_05_standardized_effects.csv"))
log_msg("  Updated standardized effects CSV with M7a/M7b")

pseudo_d_m7 <- purrr::map2_dfr(phase6_fits_reml, phase6_names, compute_level_specific_es)
pseudo_d_final <- dplyr::bind_rows(pseudo_d_all, pseudo_d_m7)
readr::write_csv(pseudo_d_final, file.path(FIGS_DIR, "mlm_06_level_specific_es.csv"))
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
log_msg("Hypotheses tested:")
log_msg("  H1a/H1b: WP/BP need frustration facets -> TI (M3/M4)")
log_msg("  H2a/H2b: WP/BP burnout facets -> TI (M3/M4)")
log_msg("  H3a/H3b: Meeting load x NF/burnout composites (M7a/M7b)")
log_msg("  H4a/H4b: PC breach/violation -> TI (M5)")
log_msg("  H5: Job satisfaction -> TI (M5)")
log_msg("  recruitment_source in M3-M7 (manuscript-mandated control)")
log_msg("=== MULTILEVEL MODEL BUILDING COMPLETE ===")

cat("\n=== Session Info ===\n")
sessionInfo()
