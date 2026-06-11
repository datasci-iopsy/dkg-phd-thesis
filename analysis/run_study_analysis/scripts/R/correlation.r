#!/usr/bin/env Rscript
# =============================================================================
# analysis/run_study_analysis/scripts/R/correlation.r
#
# Correlation analysis for the real participant panel dataset.
# Computes L2 Pearson correlations, L1 standard Pearson correlations,
# within-person repeated-measures correlations (Bakdash & Marusich, 2017)
# using both correlation::correlation (multilevel) and rmcorr::rmcorr_mat,
# and true between-person correlations (Pearson on person means + L2 vars).
# Every r matrix ships a companion *_pvalues.csv (unadjusted pairwise p)
# so downstream tables can attach significance stars.
#
# Output: SVG figures + CSV matrices -> analysis/run_study_analysis/figs/corr/
# =============================================================================

# --- [0] Libraries and setup -------------------------------------------------
library(corrplot)
library(rmcorr)
library(correlation)
library(dplyr)
library(tidyr)
library(readr)
library(here)
library(svglite)

options(tibble.width = Inf)

source(here::here("analysis", "shared", "utils", "common_utils.r"))
source(here::here("analysis", "shared", "utils", "plot_utils.r"))
source(here::here("analysis", "run_study_analysis", "utils", "data_loader.r"))
source(here::here("analysis", "run_study_analysis", "utils", "prep_levels.r"))

FIGS_DIR <- here::here("analysis", "run_study_analysis", "figs", "corr")
ensure_dir(FIGS_DIR)

#' Reshape a pairwise correlation result into a symmetric square matrix
#'
#' @param corr_obj Data frame with columns Parameter1, Parameter2, and the
#'   column named by \code{value} (e.g. "r" or "p").
#' @param value Name of the column to spread into the matrix cells.
#' @param diag_value Value placed on the diagonal (1 for r, NA for p).
#' @return Numeric square matrix with row/column names.
corr_to_matrix <- function(corr_obj, value = "r", diag_value = 1) {
    df <- as.data.frame(corr_obj)[, c("Parameter1", "Parameter2", value)]
    sym <- dplyr::bind_rows(
        df,
        dplyr::rename(df, Parameter1 = Parameter2, Parameter2 = Parameter1)
    )
    wide <- tidyr::pivot_wider(
        sym,
        names_from = Parameter2, values_from = dplyr::all_of(value)
    )
    vars <- wide$Parameter1
    mat <- as.matrix(wide[, vars])
    rownames(mat) <- vars
    diag(mat) <- diag_value
    mat
}

save_corr_svg <- make_save_base_svg(FIGS_DIR)


# =============================================================================
# [1] DATA LOADING AND PARTITIONING
# =============================================================================
log_msg("=== [1] Loading data ===")

df_raw <- load_cleaned_data()
levels <- partition_levels(df_raw)
df_l2 <- levels$l2
df_l1 <- levels$l1


# =============================================================================
# [2] L2 PEARSON CORRELATIONS
# =============================================================================
log_msg("=== [2] L2 Pearson correlations ===")

# p_adjust = "none": descriptive-table stars use unadjusted pairwise p
# (the package default is Holm, which is for inferential multiplicity control)
l2_corr <- df_l2 |>
    dplyr::select(where(is.numeric)) |>
    correlation::correlation(method = "pearson", redundant = FALSE, p_adjust = "none")

l2_sq <- corr_to_matrix(l2_corr)
l2_pq <- corr_to_matrix(l2_corr, value = "p", diag_value = NA)
log_msg("L2 correlation matrix: ", nrow(l2_sq), " x ", ncol(l2_sq))

write.csv(l2_sq, file.path(FIGS_DIR, "corr_01_l2_pearson_matrix.csv"))
write.csv(l2_pq, file.path(FIGS_DIR, "corr_01_l2_pearson_pvalues.csv"))
log_msg("Saved: corr_01_l2_pearson_matrix.csv (+ pvalues)")

save_corr_svg("corr_l2_pearson.svg", width = 12, height = 12, {
    corrplot::corrplot(
        l2_sq,
        method      = "color",
        type        = "lower",
        addCoef.col = "black",
        number.cex  = 0.55,
        title       = "L2 Pearson correlations (between-person)",
        mar         = c(0, 0, 2, 0)
    )
})


# =============================================================================
# [3] L1 POOLED PEARSON CORRELATIONS (ignores nesting -- diagnostic only)
# -----------------------------------------------------------------------------
# Pooled (total) correlations across all 966 person-timepoint rows. These
# conflate within- and between-person variance and are NOT a between-person
# estimate (that is corr_05) nor a within-person estimate (that is corr_04).
# Kept as a diagnostic to show what naive pooling would conclude.
# =============================================================================
log_msg("=== [3] L1 pooled Pearson correlations (ignores nesting) ===")

l1_corr <- df_l1 |>
    dplyr::select(-response_id, -duration) |>
    correlation::correlation(method = "pearson", redundant = FALSE, p_adjust = "none")

l1_sq <- corr_to_matrix(l1_corr)
l1_pq <- corr_to_matrix(l1_corr, value = "p", diag_value = NA)

write.csv(l1_sq, file.path(FIGS_DIR, "corr_02_l1_pooled_pearson_matrix.csv"))
write.csv(l1_pq, file.path(FIGS_DIR, "corr_02_l1_pooled_pearson_pvalues.csv"))
log_msg("Saved: corr_02_l1_pooled_pearson_matrix.csv (+ pvalues)")

save_corr_svg("corr_l1_pooled_pearson.svg", width = 10, height = 10, {
    corrplot::corrplot(
        l1_sq,
        method      = "color",
        type        = "lower",
        addCoef.col = "black",
        number.cex  = 0.65,
        title       = "L1 pooled Pearson (ignores nesting; conflates within + between)",
        mar         = c(0, 0, 2, 0)
    )
})


# =============================================================================
# [4] WITHIN-PERSON REPEATED-MEASURES CORRELATIONS
# =============================================================================
log_msg("=== [4] Within-person repeated-measures correlations ===")

# --- 4a: correlation::correlation multilevel approach -----------------------
log_msg("  [4a] correlation::correlation (multilevel = TRUE)")

mlm_corr <- df_l1 |>
    dplyr::select(-duration) |>
    correlation::correlation(
        method     = "pearson",
        multilevel = TRUE,
        redundant  = FALSE,
        p_adjust   = "none"
    )

mlm_mat <- corr_to_matrix(mlm_corr)
mlm_pmat <- corr_to_matrix(mlm_corr, value = "p", diag_value = NA)

# --- 4b: rmcorr (Bakdash & Marusich, 2017) ----------------------------------
# js_tp1_mean excluded: captured only at tp1 (9AM); NULL at tp2/tp3 by survey
# design. A within-person correlation on a tp1-only item is not interpretable.
log_msg("  [4b] rmcorr::rmcorr_mat")

rmc_vars <- c(
    "timepoint",
    "pf_mean", "cw_mean", "ee_mean",
    "comp_mean", "auto_mean", "relt_mean",
    "atcb_mean", "meetings_count", "meetings_time",
    "turnover_intention_mean"
)

df_l1_rmc <- df_l1 |>
    dplyr::select(response_id, dplyr::all_of(rmc_vars)) |>
    tidyr::drop_na()

rmc_corr <- rmcorr::rmcorr_mat(
    participant = response_id,
    variables   = rmc_vars,
    dataset     = df_l1_rmc,
    CI.level    = 0.95
)

# NaN in the rmcorr matrix occurs when SSFactor + SSresidual collapses to zero
# for a near-zero within-person correlation (numerical artifact, not missing data).
rmc_corr$matrix[is.nan(rmc_corr$matrix)] <- 0

# rmcorr p-value matrix from the pairwise summary (p.vals column); the
# diagonal and any NaN-artifact pairs stay NA (no significance claim)
rmc_pmat <- corr_to_matrix(
    rmc_corr$summary |>
        dplyr::rename(Parameter1 = measure1, Parameter2 = measure2, p = p.vals),
    value = "p", diag_value = NA
)
rmc_pmat[is.nan(rmc_pmat)] <- NA

# Align variable ordering to shared variables
shared_vars <- intersect(colnames(rmc_corr$matrix), rownames(mlm_mat))
mlm_sq <- mlm_mat[shared_vars, shared_vars]
mlm_pq <- mlm_pmat[shared_vars, shared_vars]
rmc_sq <- rmc_corr$matrix[shared_vars, shared_vars]
rmc_pq <- rmc_pmat[shared_vars, shared_vars]

log_msg("  Shared variables for comparison: ", length(shared_vars))

# corr_03 is the lme4-based partial correlation adjusted for person (a
# within-person estimate, kept only for comparison with rmcorr); the file
# was previously misnamed "_between_"
write.csv(mlm_sq, file.path(FIGS_DIR, "corr_03_mlm_within_partial_matrix.csv"))
write.csv(mlm_pq, file.path(FIGS_DIR, "corr_03_mlm_within_partial_pvalues.csv"))
write.csv(rmc_sq, file.path(FIGS_DIR, "corr_04_rmcorr_within_matrix.csv"))
write.csv(rmc_pq, file.path(FIGS_DIR, "corr_04_rmcorr_within_pvalues.csv"))
log_msg("Saved: corr_03_mlm_within_partial_matrix.csv, corr_04_rmcorr_within_matrix.csv (+ pvalues)")

# --- 4c: side-by-side comparison --------------------------------------------
save_corr_svg("corr_comparison.svg", width = 20, height = 10, {
    par(mfrow = c(1, 2))
    corrplot::corrplot(
        mlm_sq,
        method      = "color",
        type        = "lower",
        addCoef.col = "black",
        number.cex  = 0.65,
        title       = "MLM correlation (correlation pkg, multilevel = TRUE)",
        mar         = c(0, 0, 2, 0)
    )
    corrplot::corrplot(
        rmc_sq,
        method      = "color",
        type        = "lower",
        addCoef.col = "black",
        number.cex  = 0.65,
        title       = "Repeated-measures correlation (rmcorr)",
        mar         = c(0, 0, 2, 0)
    )
})

# --- 4d: individual figures --------------------------------------------------
save_corr_svg("corr_mlm.svg", width = 10, height = 10, {
    corrplot::corrplot(
        mlm_sq,
        method      = "color",
        type        = "lower",
        addCoef.col = "black",
        number.cex  = 0.70,
        title       = "MLM correlation (correlation pkg, multilevel = TRUE)",
        mar         = c(0, 0, 2, 0)
    )
})

save_corr_svg("corr_rmc.svg", width = 10, height = 10, {
    corrplot::corrplot(
        rmc_sq,
        method      = "color",
        type        = "lower",
        addCoef.col = "black",
        number.cex  = 0.70,
        title       = "Repeated-measures correlation (rmcorr)",
        mar         = c(0, 0, 2, 0)
    )
})

# =============================================================================
# [5] TRUE BETWEEN-PERSON CORRELATIONS (person means of L1 vars + L2 vars)
# -----------------------------------------------------------------------------
# Person-level Pearson correlations: each L1 variable is averaged across a
# participant's 3 timepoints into one global person-mean score (one row per
# person; NOT within-person centering), then joined with the L2 intake
# variables. This is the appropriate between-person estimate for the
# descriptives/correlations table: corr_03 (multilevel = TRUE) is a
# within-person partial correlation, and corr_01 covers only the L2 intake
# variables (no L1 person means, so it cannot fill the L1 x L2 block of a
# combined table).
# =============================================================================
log_msg("=== [5] Between-person correlations (person means + L2) ===")

l1_mean_vars <- setdiff(rmc_vars, "timepoint")

df_between <- df_l1 |>
    dplyr::group_by(response_id) |>
    dplyr::summarise(
        dplyr::across(dplyr::all_of(l1_mean_vars), ~ mean(.x, na.rm = TRUE)),
        .groups = "drop"
    ) |>
    dplyr::inner_join(df_l2, by = "response_id")

bw_corr <- df_between |>
    dplyr::select(where(is.numeric)) |>
    correlation::correlation(method = "pearson", redundant = FALSE, p_adjust = "none")

bw_sq <- corr_to_matrix(bw_corr)
bw_pq <- corr_to_matrix(bw_corr, value = "p", diag_value = NA)
log_msg("Between-person matrix: ", nrow(bw_sq), " x ", ncol(bw_sq))

write.csv(bw_sq, file.path(FIGS_DIR, "corr_05_between_person_matrix.csv"))
write.csv(bw_pq, file.path(FIGS_DIR, "corr_05_between_person_pvalues.csv"))
log_msg("Saved: corr_05_between_person_matrix.csv (+ pvalues)")


# =============================================================================
# [6] MANUSCRIPT FIGURE: between-person (L2 Pearson) + within-person (rmcorr)
# -----------------------------------------------------------------------------
# This is the primary correlation figure for the methods/results section.
# L2 Pearson is the appropriate between-person estimate; rmcorr (Bakdash &
# Marusich 2017) is the appropriate within-person estimate. The multilevel
# approach (section 4a) uses partial correlations and attenuates within-person
# associations; rmcorr preserves the full within-person signal.
# =============================================================================
log_msg("=== [6] Manuscript figure: L2 Pearson + rmcorr ===")

save_corr_svg("corr_between_within.svg", width = 24, height = 12, {
    par(mfrow = c(1, 2))
    corrplot::corrplot(
        l2_sq,
        method      = "color",
        type        = "lower",
        addCoef.col = "black",
        number.cex  = 0.75,
        tl.cex      = 0.85,
        title       = "Between-person correlations (L2 Pearson)",
        mar         = c(0, 0, 2, 0)
    )
    corrplot::corrplot(
        rmc_sq,
        method      = "color",
        type        = "lower",
        addCoef.col = "black",
        number.cex  = 0.75,
        tl.cex      = 0.85,
        title       = "Within-person correlations (rmcorr; Bakdash & Marusich 2017)",
        mar         = c(0, 0, 2, 0)
    )
})
log_msg("Saved: corr_between_within.svg")

log_msg("=== Correlation analysis complete. Figures -> ", FIGS_DIR, " ===")
