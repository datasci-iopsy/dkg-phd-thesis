#!/usr/bin/env Rscript
# =============================================================================
# analysis/run_study_analysis/scripts/R/correlation.R
#
# Correlation analysis for the real participant panel dataset.
# Computes L2 Pearson correlations, L1 standard Pearson correlations, and
# within-person repeated-measures correlations (Bakdash & Marusich, 2017)
# using both correlation::correlation (multilevel) and rmcorr::rmcorr_mat.
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
source(here::here("analysis", "run_study_analysis", "utils", "data_loader.R"))
source(here::here("analysis", "run_study_analysis", "utils", "prep_levels.R"))

FIGS_DIR <- here::here("analysis", "run_study_analysis", "figs", "corr")
ensure_dir(FIGS_DIR)

#' Reshape a correlation::correlation result into a symmetric square matrix
#'
#' @param corr_obj Data frame with columns Parameter1, Parameter2, and r.
#' @return Numeric square matrix with row/column names and diagonal equal to 1.
corr_to_matrix <- function(corr_obj) {
    df <- as.data.frame(corr_obj)[, c("Parameter1", "Parameter2", "r")]
    sym <- dplyr::bind_rows(
        df,
        dplyr::rename(df, Parameter1 = Parameter2, Parameter2 = Parameter1)
    )
    wide <- tidyr::pivot_wider(sym, names_from = Parameter2, values_from = r)
    vars <- wide$Parameter1
    mat  <- as.matrix(wide[, vars])
    rownames(mat) <- vars
    diag(mat) <- 1
    mat
}

save_corr_svg <- make_save_base_svg(FIGS_DIR)


# =============================================================================
# [1] DATA LOADING AND PARTITIONING
# =============================================================================
log_msg("=== [1] Loading data ===")

df_raw   <- load_cleaned_data()
levels   <- partition_levels(df_raw)
df_l2    <- levels$l2
df_l1    <- levels$l1


# =============================================================================
# [2] L2 PEARSON CORRELATIONS
# =============================================================================
log_msg("=== [2] L2 Pearson correlations ===")

l2_corr <- df_l2 |>
    dplyr::select(where(is.numeric)) |>
    correlation::correlation(method = "pearson", redundant = FALSE)

l2_sq <- corr_to_matrix(l2_corr)
log_msg("L2 correlation matrix: ", nrow(l2_sq), " x ", ncol(l2_sq))

write.csv(l2_sq, file.path(FIGS_DIR, "corr_01_l2_pearson_matrix.csv"))
log_msg("Saved: corr_01_l2_pearson_matrix.csv")

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
# [3] L1 STANDARD PEARSON CORRELATIONS (ignores nesting)
# =============================================================================
log_msg("=== [3] L1 standard Pearson correlations ===")

l1_corr <- df_l1 |>
    dplyr::select(-response_id, -duration) |>
    correlation::correlation(method = "pearson", redundant = FALSE)

l1_sq <- corr_to_matrix(l1_corr)

write.csv(l1_sq, file.path(FIGS_DIR, "corr_02_l1_pearson_matrix.csv"))
log_msg("Saved: corr_02_l1_pearson_matrix.csv")

save_corr_svg("corr_l1_pearson.svg", width = 10, height = 10, {
    corrplot::corrplot(
        l1_sq,
        method      = "color",
        type        = "lower",
        addCoef.col = "black",
        number.cex  = 0.65,
        title       = "L1 Pearson correlations (ignores nesting)",
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
        redundant  = FALSE
    )

mlm_mat <- corr_to_matrix(mlm_corr)

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

# Align variable ordering to shared variables
shared_vars <- intersect(colnames(rmc_corr$matrix), rownames(mlm_mat))
mlm_sq  <- mlm_mat[shared_vars, shared_vars]
rmc_sq  <- rmc_corr$matrix[shared_vars, shared_vars]

log_msg("  Shared variables for comparison: ", length(shared_vars))

write.csv(mlm_sq, file.path(FIGS_DIR, "corr_03_mlm_between_matrix.csv"))
write.csv(rmc_sq, file.path(FIGS_DIR, "corr_04_rmcorr_within_matrix.csv"))
log_msg("Saved: corr_03_mlm_between_matrix.csv, corr_04_rmcorr_within_matrix.csv")

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
# [5] MANUSCRIPT FIGURE: between-person (L2 Pearson) + within-person (rmcorr)
# -----------------------------------------------------------------------------
# This is the primary correlation figure for the methods/results section.
# L2 Pearson is the appropriate between-person estimate; rmcorr (Bakdash &
# Marusich 2017) is the appropriate within-person estimate. The multilevel
# approach (section 4a) uses partial correlations and attenuates within-person
# associations; rmcorr preserves the full within-person signal.
# =============================================================================
log_msg("=== [5] Manuscript figure: L2 Pearson + rmcorr ===")

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
