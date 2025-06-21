library(corrplot)
library(here)
library(rmcorr)
library(tidyverse)
# library(tinytable)

# options for script
options(tibble.width = Inf)

# proj root; build paths from here ;)
here::here()

# list of tables
tbls <- list()

# list of tables
tbls <- readRDS(file = here::here("r-work", "tbls_ls.rds"))

# ! data loading from files deprecated; col type is disregarded
# file_names <- c("df_processed", "df_lvl_2_vars", "df_lvl_1_vars")

# purrr::map(file_names, function(.x) {
#     readr::read_csv(here::here("r-work", paste0(.x, ".csv")))
# }) %>%
#     purrr::set_names(file_names) -> tbls

tbls$df_lvl_2_vars %>%
    dplyr::select(where(is.numeric)) %>% # only num type used
    correlation::correlation(method = "pearson", redundant = FALSE) %>%
    summary() %>%
    plot()

tbls$df_lvl_1_vars %>%
    # dplyr::select(where(is.numeric)) %>%
    correlation::correlation(method = "pearson", redundant = FALSE) %>%
    summary() %>%
    plot()

tbls$df_lvl_2_vars %>%
    dplyr::inner_join(tbls$df_lvl_1_vars, by = "id") %>%
    dplyr::select(!tidyr::ends_with("mean") & where(is.numeric)) %>%
    dplyr::relocate(time, .before = 1) %>%
    cor() %>%
    corrplot::corrplot(type = "lower", addCoef.col = "black")

tbls$df_lvl_2_vars %>%
    dplyr::inner_join(tbls$df_lvl_1_vars, by = "id") %>%
    dplyr::select(!tidyr::ends_with("mean") & where(is.numeric)) %>%
    dplyr::relocate(time, .before = 1) %>%
    # modelsummary::datasummary_correlation()
    correlation::correlation(method = "pearson", redundant = FALSE) %>%
    summary() %>%
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

corrplot::corrplot(rmc_mat$matrix, type = "lower", addCoef.col = "black")

# corr_graphs <- list()
# map(rmc_mat$models, function(.x) {
#     plot(.x)
# }) -> corr_graphs
