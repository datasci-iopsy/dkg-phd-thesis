#!/usr/bin/env Rscript
# =============================================================================
# analysis/run_synthetic_data/scripts/r/correlation.R
#
# Correlation analysis for the synthetic panel dataset.
# Computes L2 Pearson correlations, L1 standard Pearson correlations, and
# within-person repeated-measures correlations (Bakdash & Marusich, 2017)
# using both correlation::correlation (multilevel) and rmcorr::rmcorr_mat.
#
# Output: SVG figures → analysis/run_synthetic_data/figs/corr/
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

# Source shared utilities (log_msg, ensure_dir, load_config)
source(here::here("analysis", "shared", "utils", "common_utils.r"))

# --- Global settings ---------------------------------------------------------
FIGS_DIR <- here::here("analysis", "run_synthetic_data", "figs", "corr")
ensure_dir(FIGS_DIR)

#' Reshape a correlation::correlation result into a symmetric square matrix
#'
#' Pivots the long-format correlation data frame to wide, forces rows and
#' columns into the same sorted order (pivot_wider does not guarantee this),
#' and sets the diagonal to 1.
#'
#' @param corr_obj Data frame or tibble with columns "Parameter1", "Parameter2",
#'   and "r" as returned by correlation::correlation().
#' @return Numeric square matrix with row/column names and diagonal equal to 1.
corr_to_matrix <- function(corr_obj) {
    df <- as.data.frame(corr_obj)[, c("Parameter1", "Parameter2", "r")]
    sym <- dplyr::bind_rows(
        df,
        dplyr::rename(df, Parameter1 = Parameter2, Parameter2 = Parameter1)
    )
    wide  <- tidyr::pivot_wider(sym, names_from = Parameter2, values_from = r)
    vars  <- wide$Parameter1                    # row order
    mat   <- as.matrix(wide[, vars])            # columns forced to same order as rows
    rownames(mat) <- vars
    diag(mat) <- 1
    mat
}

#' Save a base R graphics plot as an SVG file via svglite
#'
#' Opens an svglite device, forces evaluation of the plotting expression,
#' closes the device, and logs the output path.
#'
#' @param filename Character; file name (not full path) for the SVG output,
#'   written into FIGS_DIR.
#' @param width  Numeric; SVG width in inches.
#' @param height Numeric; SVG height in inches.
#' @param expr   Unevaluated plotting expression (passed via force()).
#' @return Invisibly returns the full path to the saved SVG file.
save_corr_svg <- function(filename, width, height, expr) {
    path <- file.path(FIGS_DIR, filename)
    svglite::svglite(path, width = width, height = height)
    tryCatch(
        {
            force(expr)
            dev.off()
            log_msg("Saved: ", path)
        },
        error = function(e) {
            dev.off()
            stop(e)
        }
    )
    invisible(path)
}


# =============================================================================
# [1] DATA LOADING AND PARTITIONING
# =============================================================================
log_msg("=== [1] Loading data ===")

# Prefer careless-screened file; fall back to raw export with a warning
export_files <- list.files(
    here::here("analysis", "run_synthetic_data", "data", "export"),
    pattern = "^syn_qualtrics_fct_panel_responses_cleaned_.*\\.csv$",
    full.names = TRUE
)
if (length(export_files) == 0) {
    log_msg("WARNING: No cleaned data file found. Run make synthetic_data_quality first.")
    export_files <- list.files(
        here::here("analysis", "run_synthetic_data", "data", "export"),
        pattern = "^syn_qualtrics_fct_panel_responses_\\d{8}\\.csv$",
        full.names = TRUE
    )
    if (length(export_files) == 0) stop("No export CSV found in data/export/")
}
export_path <- sort(export_files, decreasing = TRUE)[1]
log_msg("Loading: ", basename(export_path))
df_raw <- readr::read_csv(export_path, show_col_types = FALSE)
log_msg("Loaded: ", nrow(df_raw), " rows x ", ncol(df_raw), " columns")

# L2: one row per participant (time-invariant variables)
df_l2 <- df_raw |>
    dplyr::distinct(response_id, .keep_all = TRUE) |>
    dplyr::select(
        response_id,
        age, ethnicity, gender, job_tenure, edu_lvl, is_remote,
        pa_mean, na_mean, br_mean, vio_mean, js_mean
    )

# L1: all rows (time-varying variables)
df_l1 <- df_raw |>
    dplyr::select(
        response_id, timepoint,
        pf_mean, cw_mean, ee_mean,
        comp_mean, auto_mean, relt_mean,
        atcb_mean, meetings_count, meetings_mins,
        turnover_intention_mean
    )

log_msg(
    "Partitioned: L2 n=", nrow(df_l2),
    "; L1 n=", nrow(df_l1), " (", dplyr::n_distinct(df_l1$response_id), " participants)"
)


# =============================================================================
# [2] L2 PEARSON CORRELATIONS
# =============================================================================
log_msg("=== [2] L2 Pearson correlations ===")

l2_corr <- df_l2 |>
    dplyr::select(where(is.numeric)) |>
    correlation::correlation(method = "pearson", redundant = FALSE)

l2_mat <- summary(l2_corr) |> as.data.frame()
log_msg("L2 correlation matrix: ", nrow(l2_mat), " pairs")

l2_sq <- corr_to_matrix(l2_corr)

write.csv(l2_sq, file.path(FIGS_DIR, "corr_01_l2_pearson_matrix.csv"))
log_msg("Saved: corr_01_l2_pearson_matrix.csv")

save_corr_svg("corr_l2_pearson.svg", width = 10, height = 10, {
    corrplot::corrplot(
        l2_sq,
        method    = "color",
        type      = "lower",
        addCoef.col = "black",
        number.cex  = 0.65,
        title     = "L2 Pearson correlations (between-person)",
        mar       = c(0, 0, 2, 0)
    )
})


# =============================================================================
# [3] L1 STANDARD PEARSON CORRELATIONS (ignores nesting)
# =============================================================================
log_msg("=== [3] L1 standard Pearson correlations ===")

l1_corr <- df_l1 |>
    dplyr::select(-response_id) |>
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
    correlation::correlation(
        method     = "pearson",
        multilevel = TRUE,
        redundant  = FALSE
    )

mlm_mat <- corr_to_matrix(mlm_corr)

# --- 4b: rmcorr (Bakdash & Marusich, 2017) ----------------------------------
log_msg("  [4b] rmcorr::rmcorr_mat")

l1_vars <- c(
    "timepoint",
    "pf_mean", "cw_mean", "ee_mean",
    "comp_mean", "auto_mean", "relt_mean",
    "atcb_mean", "meetings_count", "meetings_mins",
    "turnover_intention_mean"
)

rmc_corr <- rmcorr::rmcorr_mat(
    participant = response_id,
    variables   = l1_vars,
    dataset     = df_l1,
    CI.level    = 0.95
)

# NaN in the rmcorr matrix occurs when SSFactor + SSresidual collapses to zero
# for a near-zero within-person correlation (numerical artifact, not missing data).
# Replace NaN with 0 so corrplot renders the cell rather than displaying "?".
rmc_corr$matrix[is.nan(rmc_corr$matrix)] <- 0

# Align variable ordering to shared variables
shared_vars <- intersect(colnames(rmc_corr$matrix), rownames(mlm_mat))
mlm_sq <- mlm_mat[shared_vars, shared_vars]
rmc_sq <- rmc_corr$matrix[shared_vars, shared_vars]

log_msg("  Shared variables for comparison: ", length(shared_vars))

write.csv(mlm_sq, file.path(FIGS_DIR, "corr_03_mlm_between_matrix.csv"))
write.csv(rmc_sq, file.path(FIGS_DIR, "corr_04_rmcorr_within_matrix.csv"))
log_msg("Saved: corr_03_mlm_between_matrix.csv and corr_04_rmcorr_within_matrix.csv")

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

log_msg("=== Correlation analysis complete. Figures -> ", FIGS_DIR, " ===")
