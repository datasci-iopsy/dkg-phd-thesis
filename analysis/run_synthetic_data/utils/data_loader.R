#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# data_loader.R — Shared data loading and canonical variable definitions
#
# Provides:
#   load_cleaned_data()  — loads the most-recent cleaned export CSV
#   VARIABLE_DEFS        — canonical L1/L2 variable group definitions
#
# Used by: eda.R, correlation.R, measurement_model.R, multilevel_model.R
#
# Dependencies: here, readr, common_utils.r (log_msg) must be sourced first.
# ---------------------------------------------------------------------------


#' Load the cleaned panel export CSV produced by data_quality.R
#'
#' @param show_col_types Logical; passed to readr::read_csv (default FALSE).
#' @return A data frame with one row per participant-timepoint observation.
#'
load_cleaned_data <- function(show_col_types = FALSE) {
    export_dir  <- here::here("analysis", "run_synthetic_data", "data", "export")
    export_path <- file.path(export_dir, "syn_qualtrics_fct_panel_responses_cleaned.csv")

    if (!file.exists(export_path)) {
        stop("Cleaned export not found: ", export_path, ". Run make synthetic_data_quality first.")
    }

    log_msg("Loading: ", basename(export_path))
    df <- readr::read_csv(export_path, show_col_types = show_col_types)
    log_msg("Loaded: ", nrow(df), " rows x ", ncol(df), " columns")

    df
}


# ---------------------------------------------------------------------------
# Canonical variable group definitions
#
# All scripts in run_synthetic_data/ reference these names. Any column rename
# in the data pipeline should be updated here and nowhere else.
# ---------------------------------------------------------------------------

VARIABLE_DEFS <- list(
    # L1 (within-person, time-varying) predictor scale means.
    # ATCB (marker variable) excluded — see l1_marker_var below.
    l1_predictor_vars = c(
        "pf_mean", "cw_mean", "ee_mean",        # burnout facets (SMBM)
        "comp_mean", "auto_mean", "relt_mean",   # NF facets (PNTS)
        "meetings_count", "meetings_mins"         # meeting load indicators
    ),

    # CFA marker variable (CWC-decomposed for completeness but excluded from MLMs)
    l1_marker_var = "atcb_mean",

    # L2 (between-person, time-invariant) study and affect variables
    l2_study_vars = c(
        "pa_mean",   # Positive Affect (I-PANAS-SF)
        "na_mean",   # Negative Affect (I-PANAS-SF)
        "br_mean",   # PC Breach (Robinson & Morrison)
        "vio_mean",  # PC Violation (Robinson & Morrison)
        "js_mean"    # Job Satisfaction (single item)
    ),

    # L2 demographic covariates
    l2_demo_vars = c(
        "age", "gender", "job_tenure", "is_remote", "edu_lvl", "ethnicity"
    ),

    # Dependent variable
    dv = "turnover_intention_mean"
)
