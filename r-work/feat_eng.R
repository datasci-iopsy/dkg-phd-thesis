library(here)
library(modelsummary) # masks parameters::supported_models; insight::supported_models
# library(patchwork)
library(tidyverse)
library(summarytools) # masks tibble::view

# options for script
options(tibble.width = Inf)

# proj root; build paths from here ;)
here::here()

# * data load from file
readr::read_csv(file = here::here("r-work/claude-syn-data-raw.csv")) -> df_raw
dplyr::glimpse(df_raw)

# * create empty list for tables
tbls <- list()

# * begin feature engineering and preprocessing
df_raw %>%
    dplyr::rename_all(tolower) %>%
    dplyr::mutate(
        # * initial cleaning; factor set up
        id = stringr::str_pad(as.character(participant_id), width = 3, pad = "0"),
        time = timepoint - 1,
        time_fct = forcats::as_factor(time), # needed for glmmTMB exclusively
        ethnicity = forcats::as_factor(ethnicity),
        gender = forcats::as_factor(gender),
        job_tenure = forcats::as_factor(job_tenure),
        edu = forcats::as_factor(education),
        work_loc = forcats::as_factor(dplyr::if_else(remote_status == TRUE, "Remote", "In-office")),

        # * generate scale scores
        pa_score = rowMeans(select(., tidyr::starts_with("pa_")), na.rm = TRUE),
        na_score = rowMeans(select(., tidyr::starts_with("na_")), na.rm = TRUE),
        pcb_score = rowMeans(select(., tidyr::starts_with("pcb_")), na.rm = TRUE),
        pcv_score = rowMeans(select(., tidyr::starts_with("pcv_")), na.rm = TRUE),
        burn_pf_score = rowMeans(select(., tidyr::starts_with("pf_")), na.rm = TRUE),
        burn_cw_score = rowMeans(select(., tidyr::starts_with("cw_")), na.rm = TRUE),
        burn_ee_score = rowMeans(select(., tidyr::starts_with("ee_")), na.rm = TRUE),
        nf_comp_score = rowMeans(select(., tidyr::starts_with("nf_comp")), na.rm = TRUE),
        nf_auto_score = rowMeans(select(., tidyr::starts_with("nf_auto")), na.rm = TRUE),
        nf_rel_score = rowMeans(select(., tidyr::starts_with("nf_rel")), na.rm = TRUE),
        atcb_score = rowMeans(select(., tidyr::starts_with("blue_")), na.rm = TRUE),

        # * grand mean centering
        pa_gmc = pa_score - mean(pa_score, na.rm = TRUE),
        na_gmc = na_score - mean(na_score, na.rm = TRUE),
        pcb_gmc = pcb_score - mean(pcb_score, na.rm = TRUE),
        pcv_gmc = pcv_score - mean(pcv_score, na.rm = TRUE),
        job_sat_gmc = job_sat - mean(job_sat, na.rm = TRUE),
        burn_pf_gmc = burn_pf_score - mean(burn_pf_score, na.rm = TRUE),
        burn_cw_gmc = burn_cw_score - mean(burn_cw_score, na.rm = TRUE),
        burn_ee_gmc = burn_ee_score - mean(burn_ee_score, na.rm = TRUE),
        nf_comp_gmc = nf_comp_score - mean(nf_comp_score, na.rm = TRUE),
        nf_auto_gmc = nf_auto_score - mean(nf_auto_score, na.rm = TRUE),
        nf_rel_gmc = nf_rel_score - mean(nf_rel_score, na.rm = TRUE),
        atcb_gmc = atcb_score - mean(atcb_score, na.rm = TRUE),
        n_meetings_gmc = n_meetings - mean(n_meetings, na.rm = TRUE),
        min_meetings_gmc = min_meetings - mean(min_meetings, na.rm = TRUE),
        turnover_int_gmc = turnover_int - mean(turnover_int, na.rm = TRUE),
    ) %>%
    dplyr::group_by(id) %>%
    dplyr::mutate(
        # * calc group means
        burn_pf_grp_mean = mean(burn_pf_score, na.rm = TRUE),
        burn_cw_grp_mean = mean(burn_cw_score, na.rm = TRUE),
        burn_ee_grp_mean = mean(burn_ee_score, na.rm = TRUE),
        nf_comp_grp_mean = mean(nf_comp_score, na.rm = TRUE),
        nf_auto_grp_mean = mean(nf_auto_score, na.rm = TRUE),
        nf_rel_grp_mean = mean(nf_rel_score, na.rm = TRUE),
        atcb_grp_mean = mean(atcb_score, na.rm = TRUE),
        n_meetings_grp_mean = mean(n_meetings, na.rm = TRUE),
        min_meetings_grp_mean = mean(min_meetings, na.rm = TRUE),
        turnover_int_grp_mean = mean(turnover_int, na.rm = TRUE),

        # * group mean centering: # https://www.lesahoffman.com/PSYC944/944_Lecture09_TVPredictors_Fluctuation.pdf
        burn_pf_pmc = burn_pf_score - burn_pf_grp_mean,
        burn_cw_pmc = burn_cw_score - burn_cw_grp_mean,
        burn_ee_pmc = burn_ee_score - burn_ee_grp_mean,
        nf_comp_pmc = nf_comp_score - nf_comp_grp_mean,
        nf_auto_pmc = nf_auto_score - nf_auto_grp_mean,
        nf_rel_pmc = nf_rel_score - nf_rel_grp_mean,
        atcb_pmc = atcb_score - atcb_grp_mean,
        n_meetings_pmc = n_meetings - n_meetings_grp_mean,
        min_meetings_pmc = min_meetings - min_meetings_grp_mean,
        turnover_int_pmc = turnover_int - turnover_int_grp_mean,
    ) %>%
    dplyr::ungroup() -> tbls[["df_processed"]]

dplyr::glimpse(tbls$df_processed)
# modelsummary::datasummary_skim(tbls$df_processed[, -1])
# summarytools::dfSummary(tbls$df_processed[, -1]) %>%
#     summarytools::stview()

# * level 2 variables
tbls$df_processed %>%
    dplyr::select(
        id,
        age,
        ethnicity,
        gender,
        job_tenure,
        edu,
        work_loc,
        pa_score,
        na_score,
        pcb_score,
        pcv_score,
        job_sat
    ) %>%
    dplyr::distinct() -> tbls[["df_lvl_2_vars"]]

# tbls$df_lvl_2_vars %>%
#     summarytools::dfSummary() %>%
#     summarytools::stview()

# tbls$df_lvl_2_vars[, -1] %>%
#     summarytools::descr() %>%
#     summarytools::stview()

# tbls$df_lvl_2_vars[, -1] %>%
#     dplyr::select(where(is.factor)) %>%
#     summarytools::freq() %>%
#     summarytools::stview()

# * level 1 variables
tbls$df_processed %>%
    dplyr::select(
        id,
        time,
        time_fct,
        burn_pf_score,
        burn_cw_score,
        burn_ee_score,
        nf_comp_score,
        nf_auto_score,
        nf_rel_score,
        atcb_score,
        n_meetings,
        min_meetings,
        turnover_int
    ) -> tbls[["df_lvl_1_vars"]]

# tbls$df_lvl_1_vars %>%
#     summarytools::dfSummary() %>%
#     summarytools::stview()

# tbls$df_lvl_1_vars %>%
#     summarytools::descr() %>%
#     summarytools::stview()

# * level 1 variables with group means
tbls$df_processed %>%
    dplyr::select(
        id,
        time,
        time_fct,
        burn_pf_grp_mean,
        burn_cw_grp_mean,
        burn_ee_grp_mean,
        nf_comp_grp_mean,
        nf_auto_grp_mean,
        nf_rel_grp_mean,
        atcb_grp_mean,
        n_meetings_grp_mean,
        min_meetings_grp_mean,
        turnover_int
    ) -> tbls[["df_lvl_1_grp_mean_vars"]]

# * download files
purrr::iwalk(tbls, function(.x, .y) {
    readr::write_csv(.x, file = here::here("r-work", paste0(.y, ".csv")))
})
