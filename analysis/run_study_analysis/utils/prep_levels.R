#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# prep_levels.R -- L1/L2 level partitioning
#
# Provides:
#   partition_levels(df, defs)
#     Splits the cleaned panel data into L1 (within-person, all rows) and
#     L2 (between-person, one row per participant). Column selection is
#     driven by VARIABLE_DEFS so renames propagate automatically.
#
# Prerequisites (caller must source before using):
#   analysis/shared/utils/common_utils.r  -- log_msg()
#   analysis/run_study_analysis/utils/data_loader.R  -- VARIABLE_DEFS
# ---------------------------------------------------------------------------


#' Partition cleaned panel data into L1 and L2 levels
#'
#' @param df  Data frame from load_cleaned_data() or load_raw_data().
#' @param defs  Variable group list; defaults to VARIABLE_DEFS.
#' @return Named list with elements \code{l1} (all rows) and \code{l2}
#'   (one row per participant).
#'
partition_levels <- function(df, defs = VARIABLE_DEFS) {
    # L2: one row per participant; all time-invariant variables
    l2_cols <- c(
        "response_id",
        defs$l2_study_vars,
        defs$l2_extra_vars,
        defs$l2_demo_vars
    )

    l2 <- df |>
        dplyr::distinct(response_id, .keep_all = TRUE) |>
        dplyr::select(dplyr::all_of(l2_cols))

    # L1: all rows; time-varying predictors, marker, tp1-only supplement, DV
    l1_cols <- c(
        "response_id",
        "timepoint",
        "duration",
        defs$l1_predictor_vars,
        defs$l1_marker_var,
        defs$l1_tp1_only,
        defs$dv
    )

    l1 <- df |>
        dplyr::select(dplyr::all_of(l1_cols))

    log_msg(
        "partition_levels: L2 n=", nrow(l2),
        " participants; L1 n=", nrow(l1),
        " (", dplyr::n_distinct(l1$response_id), " x ",
        dplyr::n_distinct(l1$timepoint), " timepoints)"
    )

    list(l1 = l1, l2 = l2)
}
