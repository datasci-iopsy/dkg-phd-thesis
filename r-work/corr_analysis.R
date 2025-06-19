library(corrplot)
library(easystats)
library(here)
library(rmcorr)
# library(tinytable)
library(tidyverse)


# options for script
options(tibble.width = Inf)

# proj root; build paths from here ;)
here::here()

file_names <- c("df_processed", "df_lvl_1_vars", "df_lvl_1_grp_mean_vars", "df_lvl_2_vars")
tbls <- list()

# * data load
purrr::map(file_names, function(.x) {
    readr::read_csv(here::here("r-work", paste0(.x, ".csv")))
}) %>%
    purrr::set_names(file_names) -> tbls

tbls$df_lvl_2_vars[, -1] %>%
    correlation::correlation(method = "pearson", redundant = FALSE) %>%
    summary() %>%
    plot()

tbls$df_lvl_1_vars[, -1] %>%
    correlation::correlation(method = "pearson", redundant = FALSE) %>%
    summary() %>%
    plot()

tbls$df_lvl_2_vars %>%
    dplyr::inner_join(tbls$df_lvl_1_vars, by = "id") %>%
    dplyr::relocate(c(time, time_fct), .after = age) %>%
    # modelsummary::datasummary_correlation()
    correlation::correlation(method = "pearson", redundant = FALSE) %>%
    summary() %>%
    plot()

tbls$df_lvl_2_vars %>%
    dplyr::inner_join(tbls$df_lvl_1_grp_mean_vars, by = "id") %>%
    dplyr::relocate(c(time, time_fct), .after = age) %>%
    # modelsummary::datasummary_correlation()
    correlation::correlation(method = "pearson", redundant = FALSE) %>%
    summary() %>%
    plot()

# ! repeated measures violate the independence assumption; try alt approach
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
