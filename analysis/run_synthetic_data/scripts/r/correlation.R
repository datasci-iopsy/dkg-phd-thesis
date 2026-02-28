library(corrplot)
library(here)
library(rmcorr)
library(dplyr)
library(readr)
library(correlation)
library(tidyr)
library(see)
# library(tinytable)

# options for script
options(tibble.width = Inf)

# proj root; build paths from here ;)
here::here()

# Load fact table exported from BigQuery via scripts/syn_export_for_r.sh
readr::read_csv(
    here::here("analysis", "run_synthetic_data", "data", "export", "syn_qualtrics_fct_panel_responses_20260227.csv"),
    show_col_types = TRUE
) -> df_raw

list() -> tbls

# L2: one row per participant (time-invariant variables)
df_raw |>
    dplyr::select(
        response_id,
        age,
        ethnicity,
        gender,
        job_tenure,
        edu_lvl,
        is_remote,
        pa_mean,
        na_mean,
        br_mean,
        vio_mean,
        js_mean
    ) -> tbls$lvl_2_vars

# L1: all rows (time-varying variables)
# Renamed to match the rmcorr_mat variables vector below
df_raw |>
    dplyr::select(
        response_id,
        timepoint,
        pf_mean,
        cw_mean,
        ee_mean,
        comp_mean,
        auto_mean,
        relt_mean,
        atcb_mean,
        meetings_count,
        meetings_mins,
        turnover_intention_mean
    ) -> tbls$lvl_1_vars

tbls$lvl_2_vars |>
    dplyr::select(where(is.numeric)) |> # only num type used
    correlation::correlation(method = "pearson", redundant = FALSE) |>
    summary() |>
    plot()

# non-multilevel correlation
tbls$lvl_1_vars |>
    dplyr::select(-response_id) |>
    correlation::correlation(method = "pearson", redundant = FALSE) |>
    summary() |>
    plot()

# corrected multilevel correlation
tbls$lvl_1_vars |>
    correlation::correlation(
        method = "pearson",
        multilevel = TRUE,
        redundant = FALSE
    ) -> mlm_corr

# mlm_corr |>
#     summary() |>
#     plot()

# ! repeated measures violate the independence assumption; try alt approach: Bakdash, J. Z., & Marusich, L. R. (2017)
rmcorr::rmcorr_mat(
    participant = response_id,
    variables = c(
        "timepoint",
        "pf_mean",
        "cw_mean",
        "ee_mean",
        "comp_mean",
        "auto_mean",
        "relt_mean",
        "atcb_mean",
        "meetings_count",
        "meetings_mins",
        "turnover_intention_mean"
    ),
    dataset = tbls$lvl_1_vars,
    CI.level = 0.95
) -> rmc_corr

# rmc_mat$matrix |>
#     corrplot::corrplot(
#         method = "number",
#         type = "lower",
#         diag = FALSE
#     )

# figs_dir <- here::here("analysis", "run_synthetic_data", "figs")
# dir.create(figs_dir, recursive = TRUE, showWarnings = FALSE)

# jpeg(filename = file.path(figs_dir, "rmc_fig.jpeg"), width = 800, height = 800)
# --- Compare mlm_corr (correlation::correlation, multilevel) vs rmc_corr (rmcorr::rmcorr_mat) ---
#
# mlm_corr is a long-format easycorrelation data frame; each row is one pair (r as numeric).
# rmc_corr$matrix is already a square numeric matrix.
# Reshape mlm_corr into a square matrix so corrplot can handle both uniformly.

mlm_df <- as.data.frame(mlm_corr)[, c("Parameter1", "Parameter2", "r")]

# Symmetrize: add transposed rows so pivot_wider fills both triangles
mlm_sym <- dplyr::bind_rows(
    mlm_df,
    dplyr::rename(mlm_df, Parameter1 = Parameter2, Parameter2 = Parameter1)
)
mlm_wide <- tidyr::pivot_wider(mlm_sym, names_from = Parameter2, values_from = r)
mlm_mat <- as.matrix(mlm_wide[, -1])
rownames(mlm_mat) <- mlm_wide$Parameter1
diag(mlm_mat) <- 1 # diagonal is always 1 by definition

# Align variable ordering to rmc_corr$matrix (keep only shared variables)
shared_vars <- intersect(colnames(rmc_corr$matrix), rownames(mlm_mat))
mlm_mat <- mlm_mat[shared_vars, shared_vars]
rmc_mat <- rmc_corr$matrix[shared_vars, shared_vars]

figs_dir <- here::here("analysis", "run_synthetic_data", "figs")
dir.create(figs_dir, recursive = TRUE, showWarnings = FALSE)

# --- Side-by-side comparison ---
jpeg(filename = file.path(figs_dir, "corr_comparison.jpeg"), width = 1800, height = 900)
par(mfrow = c(1, 2))
corrplot::corrplot(
    mlm_mat,
    method = "color", type = "lower",
    addCoef.col = "black", number.cex = 0.65,
    title = "MLM correlation (correlation pkg, multilevel = TRUE)",
    mar = c(0, 0, 2, 0)
)
corrplot::corrplot(
    rmc_mat,
    method = "color", type = "lower",
    addCoef.col = "black", number.cex = 0.65,
    title = "Repeated-measures correlation (rmcorr)",
    mar = c(0, 0, 2, 0)
)
dev.off()

# --- Individual figures ---
jpeg(filename = file.path(figs_dir, "mlm_corr.jpeg"), width = 900, height = 900)
corrplot::corrplot(
    mlm_mat,
    method = "color", type = "lower",
    addCoef.col = "black", number.cex = 0.7,
    title = "MLM correlation (correlation pkg, multilevel = TRUE)",
    mar = c(0, 0, 2, 0)
)
dev.off()

jpeg(filename = file.path(figs_dir, "rmc_corr.jpeg"), width = 900, height = 900)
corrplot::corrplot(
    rmc_mat,
    method = "color", type = "lower",
    addCoef.col = "black", number.cex = 0.7,
    title = "Repeated-measures correlation (rmcorr)",
    mar = c(0, 0, 2, 0)
)
dev.off()
