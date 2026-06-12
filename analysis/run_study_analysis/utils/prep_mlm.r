#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# prep_mlm.r -- MLM centering and variable preparation
#
# Provides:
#   prepare_mlm_frame(df, defs)
#     Applies all centering, coding, and composite construction needed
#     before fitting lmer models. Returns a model-ready data frame with
#     _within/_between (CWC) and _c (grand-mean centered) columns.
#
# Steps:
#   1. time_c: timepoint - 1 (intercept = first observation)
#   2. CWC decomposition of L1 predictors via datawizard::demean()
#   3. CWC decomposition of ATCB marker (for CFA/descriptive use only)
#   4. Centering verification via verify_centering() -- hard stop on failure
#   5. Grand-mean centering of L2 study variables (*_c suffix)
#   6. Demographic coding: age_c, factor() categoricals, is_remote integer,
#      recruitment_source factor
#   7. Composite construction: burnout_mean and nf_mean, then CWC-decomposed
#      (used in M7a/M7b moderation models only)
#
# Prerequisites (caller must source before using):
#   analysis/shared/utils/common_utils.r   -- log_msg()
#   analysis/shared/utils/mlm_utils.r      -- verify_centering()
#   analysis/run_study_analysis/utils/data_loader.r  -- VARIABLE_DEFS
# ---------------------------------------------------------------------------


#' Prepare a model-ready MLM data frame
#'
#' @param df    Data frame from load_cleaned_data() (957 rows x 319 persons).
#' @param defs  Variable group list; defaults to VARIABLE_DEFS.
#' @return The input data frame augmented with _within/_between/_c columns
#'   and coded demographic variables.
#'
prepare_mlm_frame <- function(df, defs = VARIABLE_DEFS) {
    # [1] Time centering: intercept at first timepoint
    df <- df |>
        dplyr::mutate(time_c = timepoint - 1)

    # [2] CWC decomposition of L1 predictors
    #     Produces {var}_within (person-mean centered) and {var}_between
    #     (grand-mean centered person mean) for each predictor.
    log_msg("  Applying CWC decomposition for L1 predictors...")
    df <- datawizard::demean(df, select = defs$l1_predictor_vars, by = "response_id")

    # ATCB marker decomposed separately; excluded from MLM formulas
    df <- datawizard::demean(df, select = defs$l1_marker_var, by = "response_id")

    # [3] Verify within-person means are ~0 after centering
    centering_check <- verify_centering(
        df,
        id_col      = "response_id",
        within_vars = paste0(defs$l1_predictor_vars, "_within")
    )
    log_msg(
        "  Max within-person mean deviation: ",
        round(centering_check$max_deviation, 8),
        " (should be ~0)"
    )
    if (!centering_check$all_pass) {
        stop("Centering verification failed -- check datawizard::demean() output")
    }

    # [4] L2 grand-mean centering for study variables
    for (v in defs$l2_study_vars) {
        df[[paste0(v, "_c")]] <- df[[v]] - mean(df[[v]], na.rm = TRUE)
    }

    # L2 grand-mean centering for environmental control variables (JIS, DES)
    for (v in defs$l2_control_vars) {
        df[[paste0(v, "_c")]] <- df[[v]] - mean(df[[v]], na.rm = TRUE)
    }

    # [5] Demographic coding
    df <- df |>
        dplyr::mutate(
            age_c              = age - mean(age, na.rm = TRUE),
            gender             = factor(gender),
            job_tenure         = factor(job_tenure),
            is_remote          = as.integer(is_remote),
            edu_lvl            = factor(edu_lvl),
            ethnicity          = factor(ethnicity),
            recruitment_source = factor(recruitment_source)
        )

    # [6] Phase 6 composites (M7a/M7b moderation only)
    log_msg("  Creating composites: burnout_mean, nf_mean...")
    df$burnout_mean <- rowMeans(
        df[, c("pf_mean", "cw_mean", "ee_mean")],
        na.rm = TRUE
    )
    df$nf_mean <- rowMeans(
        df[, c("comp_mean", "auto_mean", "relt_mean")],
        na.rm = TRUE
    )
    df <- datawizard::demean(
        df,
        select = c("burnout_mean", "nf_mean"),
        by     = "response_id"
    )
    log_msg("  Composites ready: burnout_mean_within/between, nf_mean_within/between")

    log_msg("  MLM frame ready. Total columns: ", ncol(df))
    df
}
