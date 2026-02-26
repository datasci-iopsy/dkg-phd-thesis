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
df_raw <- readr::read_csv(
    here::here("analysis", "run_synthetic_data", "data", "export", "fct_syn_all_responses_20260226.csv"),
    show_col_types = FALSE
)

# L2: one row per participant (time-invariant variables)
df_lvl_2_vars <- df_raw |>
    dplyr::select(
        id = response_id,
        time_zone, age, ethnicity, gender, job_tenure, edu_lvl, is_remote,
        pa_mean, na_mean, br_mean, vio_mean, js_mean
    ) |>
    dplyr::distinct(id, .keep_all = TRUE)

# L1: all rows (time-varying variables)
# Renamed to match the rmcorr_mat variables vector below
df_lvl_1_vars <- df_raw |>
    dplyr::select(
        id = response_id,
        time = timepoint,
        burn_pf_score = pf_mean,
        burn_cw_score = cw_mean,
        burn_ee_score = ee_mean,
        nf_comp_score = comp_mean,
        nf_auto_score = auto_mean,
        nf_rel_score = relt_mean,
        atcb_score = atcb_mean,
        n_meetings = meetings_count,
        min_meetings = meetings_mins,
        turnover_int = turnover_intention_mean
    )

tbls <- list(
    df_lvl_2_vars = df_lvl_2_vars,
    df_lvl_1_vars = df_lvl_1_vars
)

tbls$df_lvl_2_vars |>
    dplyr::select(where(is.numeric)) |> # only num type used
    correlation::correlation(method = "pearson", redundant = FALSE) |>
    summary() |>
    plot()

tbls$df_lvl_1_vars |>
    # dplyr::select(where(is.numeric)) |>
    correlation::correlation(method = "pearson", redundant = FALSE) |>
    summary() |>
    plot()

tbls$df_lvl_2_vars |>
    dplyr::inner_join(tbls$df_lvl_1_vars, by = "id") |>
    dplyr::select(!tidyr::ends_with("mean") & where(is.numeric)) |>
    dplyr::relocate(time, .before = 1) |>
    cor() |>
    corrplot::corrplot(type = "lower", addCoef.col = "black")

tbls$df_lvl_2_vars |>
    dplyr::inner_join(tbls$df_lvl_1_vars, by = "id") |>
    dplyr::select(!tidyr::ends_with("mean") & where(is.numeric)) |>
    dplyr::relocate(time, .before = 1) |>
    # modelsummary::datasummary_correlation()
    correlation::correlation(method = "pearson", redundant = FALSE) |>
    summary() |>
    plot()

# ! repeated measures violate the independence assumption; try alt approach: Bakdash, J. Z., & Marusich, L. R. (2017)
rmcorr::rmcorr_mat(
    participant = id,
    variables = c(
        "burn_pf_score",
        "burn_cw_score",
        "burn_ee_score",
        "nf_comp_score",
        "nf_auto_score",
        "nf_rel_score",
        "atcb_score",
        "n_meetings",
        "min_meetings",
        "turnover_int"
    ),
    dataset = tbls$df_lvl_1_vars,
    CI.level = 0.95
) -> rmc_mat
rmc_mat

figs_dir <- here::here("analysis", "run_synthetic_data", "figs")
dir.create(figs_dir, recursive = TRUE, showWarnings = FALSE)

jpeg(filename = file.path(figs_dir, "rmc_fig.jpeg"), width = 800, height = 800)
rmc_fig <- corrplot::corrplot(rmc_mat$matrix, type = "lower", addCoef.col = "black")
dev.off()
