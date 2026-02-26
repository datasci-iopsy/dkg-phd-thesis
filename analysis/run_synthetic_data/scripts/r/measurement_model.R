library(lavaan)
library(semTools)
# library(tidyverse)

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

# claude code Lai (2021): https://www.perplexity.ai/search/i-would-like-you-to-review-the-I0j.67PPRAKO6lJCNR_dMw#3
# blog from Lai: https://quantscience.rbind.io/posts/2022-11-13-multilevel-composite-reliability/
# semTools repo: https://github.com/marklhc/mcfa_reliability_supp/blob/master/compare_semTools.md
# https://stats.oarc.ucla.edu/r/seminars/rcfa/#s4
"level: 1
    POS_AFF =~ pa1 + pa2 + pa3 + pa4 + pa5
    NEG_AFF =~ na1 + na2 + na3 + na4 + na5
    PCB =~ pcb1 + pcb2 + pcb_3 + pcb_4 + pcb_5
    PCV =~ pcv_1 + pcv_2 + pcv_3 + pcv_4
    JOB_SAT =~ job_sat
    PF =~ pf_1 + pf_2 + pf_3 + pf_4 + pf_5 + pf_6
    CW =~ cw_1 + cw_2 + cw_3 + cw_4 + cw_5
    EE =~ ee_1 + ee_2 + ee_3
    NF_COMP =~ nf_comp_1 + nf_comp_2 + nf_comp_3 + nf_comp_4
    NF_AUTO =~ nf_auto_1 + nf_auto_2 + nf_auto_3 + nf_auto_4
    NF_REL =~ nf_rel_1 + nf_rel_2 + nf_rel_3 + nf_rel_4
    ATCB =~ blue_1 + blue_2 + blue_3 + blue_4
    TURNOVER =~ turnover_int
level: 2
    POS_AFF =~ pa_1 + pa_2 + pa_3 + pa_4 + pa_5
    NEG_AFF =~ na_1 + na_2 + na_3 + na_4 + na_5
    PCB =~ pcb_1 + pcb_2 + pcb_3 + pcb_4 + pcb_5
    PCV =~ pcv_1 + pcv_2 + pcv_3 + pcv_4
    JOB_SAT =~ job_sat
    PF =~ pf_1 + pf_2 + pf_3 + pf_4 + pf_5 + pf_6
    CW =~ cw_1 + cw_2 + cw_3 + cw_4 + cw_5
    EE =~ ee_1 + ee_2 + ee_3
    NF_COMP =~ nf_comp_1 + nf_comp_2 + nf_comp_3 + nf_comp_4
    NF_AUTO =~ nf_auto_1 + nf_auto_2 + nf_auto_3 + nf_auto_4
    NF_REL =~ nf_rel_1 + nf_rel_2 + nf_rel_3 + nf_rel_4
    ATCB =~ blue_1 + blue_2 + blue_3 + blue_4
    TURNOVER =~ turnover_int" -> mcfa_full_mod

lavaan::cfa(
    model = mcfa_full_mod,
    data = tbls$df_item_lvl_vars,
    cluster = "id",
    estimator = "MLR", # https://www.perplexity.ai/search/i-would-like-you-to-review-the-I0j.67PPRAKO6lJCNR_dMw#4
    optim.method = "nlminb", # options(nlminb, BFGS, L-BFGS-B, GN)
    # optim.force.converged = TRUE
    # std.lv = TRUE,
    # verbose = FALSE
    # se = "robust"
) -> mcfa_full_mod_fit

# if necessary, see model fit warnings
warnings()

summary(mcfa_full_mod_fit, fit.measures = TRUE, standardized = TRUE)
# lavaan::fitMeasures(mcfa_full_mod_fit) # extract specific fit measures

# * calculate composite reliabilities based on Lai (2021)
compRelSEM(
    object = mcfa_full_mod_fit,
    tau.eq = FALSE,
    config = c(
        "PF", "CW", "EE", "NF_COMP", "NF_AUTO", "NF_REL", "ATCB", "TURNOVER",
        "POS_AFF", "NEG_AFF", "PCB", "PCV", "JOB_SAT"
    ),
    shared = c(
        "PF", "CW", "EE", "NF_COMP", "NF_AUTO", "NF_REL", "ATCB", "TURNOVER",
        "POS_AFF", "NEG_AFF", "PCB", "PCV", "JOB_SAT"
    ),
)

# ! NOTE: single-item omega reliabilities cannot be calculated
# if necessary see model fit warnings
warnings()
