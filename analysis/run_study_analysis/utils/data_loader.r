#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# data_loader.r -- Shared data loading and canonical variable definitions
#
# Provides:
#   load_cleaned_data()  -- loads the cleaned export CSV produced by data_quality.r
#   VARIABLE_DEFS        -- canonical L1/L2 variable group definitions
#
# Used by: eda.r, correlation.r, measurement_model.r, multilevel_model.r
#
# Dependencies: here, readr, common_utils.r (log_msg) must be sourced first.
# ---------------------------------------------------------------------------


#' Load the cleaned panel export CSV produced by data_quality.r
#'
#' @param show_col_types Logical; passed to readr::read_csv (default FALSE).
#' @return A data frame with one row per participant-timepoint observation.
#'
load_cleaned_data <- function(show_col_types = FALSE) {
    export_dir <- here::here("analysis", "run_study_analysis", "data", "export")
    raw_path <- file.path(export_dir, "qualtrics_fct_panel_responses.csv")
    export_path <- file.path(export_dir, "qualtrics_fct_panel_responses_cleaned.csv")

    require_fresh(
        targets       = export_path,
        prerequisites = raw_path,
        remediation   = "make study_data_quality"
    )

    log_msg("Loading: ", basename(export_path))
    df <- readr::read_csv(export_path, show_col_types = show_col_types)
    log_msg("Loaded: ", nrow(df), " rows x ", ncol(df), " columns")

    df
}


# ---------------------------------------------------------------------------
# Canonical variable group definitions
#
# All scripts in run_study_analysis/ reference these names. Any column rename
# in the data pipeline should be updated here and nowhere else.
# ---------------------------------------------------------------------------

VARIABLE_DEFS <- list(
    # L1 (within-person, time-varying) predictor scale means.
    # ATCB (marker variable) excluded -- see l1_marker_var below.
    l1_predictor_vars = c(
        "pf_mean", "cw_mean", "ee_mean", # burnout facets (SMBM)
        "comp_mean", "auto_mean", "relt_mean", # NF facets (PNTS)
        "meetings_count", # meeting count (meetings_num, capped at 8)
        "meetings_time" # duration in minutes (supplement backfill; NULL where unmatched)
    ),

    # CFA marker variable (CWC-decomposed for completeness but excluded from MLMs)
    l1_marker_var = "atcb_mean",

    # L2 (between-person, time-invariant) study and affect variables
    l2_study_vars = c(
        "pa_mean", # Positive Affect (I-PANAS-SF)
        "na_mean", # Negative Affect (I-PANAS-SF)
        "br_mean", # PC Breach (Robinson & Morrison)
        "vio_mean", # PC Violation (Robinson & Morrison)
        "js_mean" # Job Satisfaction (single item)
    ),

    # L2 environmental control variables (mandatory; grand-mean centered via prep_mlm.r)
    l2_control_vars = c(
        "jis_mean", # Job Insecurity (JIS; Sverke et al. 2002)
        "des_mean" # Desirability of Movement (DES; Griffeth et al. 2000)
    ),

    # L1 supplementary item: JS captured at tp1 (9AM survey) only.
    # NULL at tp2/tp3 by survey design (item placed after survey end; unrecoverable).
    # Not a time-varying predictor in the MLM sense; use only for tp1-specific analyses.
    l1_tp1_only = "js_tp1_mean",

    # L2 demographic covariates
    l2_demo_vars = c(
        "age", "gender", "job_tenure", "is_remote", "edu_lvl", "ethnicity",
        "recruitment_source" # CloudResearch vs snowball (derived from connect_id)
    ),

    # Dependent variable
    dv = "turnover_intention_mean"
)
