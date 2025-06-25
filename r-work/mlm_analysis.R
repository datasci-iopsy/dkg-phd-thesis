library(easystats)
# library(ggeffects) # masks modelbased::pool_predicts; easystats::install_latest
library(ggplot2)
# library(glmmTMB) # todo: determine if necessary; https://glmmtmb.r-universe.dev/glmmTMB
library(modelsummary) # masks parameters::supported_models; insights::supported_models
library(multilevelmod) # masks insight::null_model
library(nlme)
library(lme4) # masks nlme::lmList
library(lmerTest) # masks lme4::lmer; stats::step
# library(marginaleffects)
library(sjPlot)
library(tidymodels)
library(tidyverse)

# options for script
options(tibble.width = Inf)

# proj root; build paths from here ;)
here::here()

# list of tables
list() -> tbl_ls

# list of tables
readRDS(file = here::here("r-work", "tbls_ls.rds")) -> tbl_ls

# full data
tbl_ls$df_lvl_1_vars %>%
    dplyr::left_join(tbl_ls$df_lvl_2_vars, by = "id") |>
    dplyr::inner_join(tbl_ls$df_cent_vars, by = c("id", "time", "time_fct")) -> dat

# quick review of dataframe
dplyr::glimpse(dat)

# # quick viz
# dat %>%
#     # group_by(id) %>%
#     # dplyr::slice_sample(n = 10) %>%
#     dplyr::filter(id %in% sample(id, size = 50)) %>%
#     ggplot2::ggplot(aes(x = time_fct, y = nf_comp_score, group = id)) +
#     ggplot2::geom_point() +
#     ggplot2::geom_line()
# # geom_smooth(
# #     aes(group = job_tenure, color = job_tenure),
# #     method = "lm", se = FALSE, linewidth = 1
# # ) #-> p1

# ggplot2::ggplot(data = dat, aes(x = time, y = turnover_int, group = id)) +
#     geom_line() +
#     geom_point()
# # geom_smooth(
# #     aes(group = id, color = kidgen),
# #     method = "lm", se = FALSE, linewidth = 1
# # ) #-> p2

# patchwork::wrap_plots(p1, p2)

# * list comprising modeling specifications
list() -> mod_spec_ls

# null model specs
parsnip::linear_reg() %>%
    parsnip::set_engine(
        engine = "lme",
        random = ~ 1 | id,
        correlation = NULL,
        method = "ML"
        # control = lmeControl(
        #     maxIter = 1000,
        #     msMaxIter = 1000,
        #     tolerance = 1e-6,
        #     niterEM = 50,
        #     opt = "optim",
        #     optimMethod = "L-BFGS-B",
        # )
    ) -> mod_spec_ls[["lme_fix_slp_un"]]

parsnip::linear_reg() %>%
    parsnip::set_engine(
        engine = "lme",
        random = ~ 1 | id,
        correlation = corAR1(form = ~ 1 | id),
        method = "ML"
        # control = lmeControl(
        #     maxIter = 1000,
        #     msMaxIter = 1000,
        #     tolerance = 1e-6,
        #     niterEM = 50,
        #     opt = "optim",
        #     optimMethod = "L-BFGS-B"
        # )
    ) -> mod_spec_ls[["lme_fix_slp_ar1"]]

parsnip::linear_reg() %>%
    parsnip::set_engine(
        engine = "lme",
        random = ~ 1 | id,
        correlation = corSymm(form = ~ 1 | id),
        method = "ML"
        # control = lmeControl(
        #     maxIter = 1000,
        #     msMaxIter = 1000,
        #     tolerance = 1e-6,
        #     niterEM = 50,
        #     opt = "optim",
        #     optimMethod = "L-BFGS-B"
        # )
    ) -> mod_spec_ls[["lme_fix_slp_symm"]]

# * check required packages for model specifications
lapply(mod_spec_ls, function(.x) {
    parsnip::required_pkgs(.x)
})

#* list comprising sets of variable names
list() -> var_name_ls

# list comprising time-varying scale scores
names(dat) %>%
    stringr::str_subset("^((burn|nf|atcb).*score|turnover_int)$") -> var_name_ls[["lvl_1_scale_scores"]]

# list comprising group means for level 1 variables
names(dat) %>%
    stringr::str_subset("grp") -> var_name_ls[["lvl_1_grp_means"]]

# list comprising time-varying group mean centered variables
names(dat) %>%
    stringr::str_subset("pmc") -> var_name_ls[["lvl_1_pmc_vars"]]

# list comprising time-invariant grand mean centered variables
names(dat) %>%
    stringr::str_subset("^(pa|na|pcb|pcv|job_sat)_gmc$") -> var_name_ls[["lvl_2_gmc_vars"]]

# * mixed modeling list
list() -> mod_fit_ls # list to hold models

purrr::set_names(var_name_ls$lvl_1_scale_scores) %>%
    lapply(., function(.x) {
        mod_spec_ls$lme_fix_slp_un %>%
            parsnip::fit(as.formula(paste(.x, " ~ 1")), data = dat) %>%
            parsnip::extract_fit_engine()
    }) -> mod_fit_ls[["null"]][["lme_fix_slp_un"]]

purrr::set_names(var_name_ls$lvl_1_scale_scores) %>%
    lapply(., function(.x) {
        mod_spec_ls$lme_fix_slp_ar1 %>%
            parsnip::fit(as.formula(paste(.x, " ~ 1")), data = dat) %>%
            parsnip::extract_fit_engine()
    }) -> mod_fit_ls[["null"]][["lme_fix_slp_ar1"]]

purrr::set_names(var_name_ls$lvl_1_scale_scores) %>%
    lapply(., function(.x) {
        mod_spec_ls$lme_fix_slp_symm %>%
            parsnip::fit(as.formula(paste(.x, " ~ 1")), data = dat) %>%
            parsnip::extract_fit_engine()
    }) -> mod_fit_ls[["null"]][["lme_fix_slp_symm"]]

# lapply(mod_fit_ls$null_lme_fix_slp_un, function(.x) {
#     performance::check_model(.x)
# })

# lapply(mod_fit_ls$null_lme_rand_slp_ar1, function(.x) {
#     performance::check_model(.x)
# })

list() -> icc_ls

lapply(mod_fit_ls$null$lme_fix_slp_un, function(.x) {
    performance::icc(.x)
}) -> icc_ls[["lme_fix_slp_un"]]


lapply(mod_fit_ls$null$lme_fix_slp_ar1, function(.x) {
    performance::icc(.x)
}) -> icc_ls[["lme_rand_slp_ar1"]]

lapply(mod_fit_ls$null$lme_fix_slp_symm, function(.x) {
    performance::icc(.x)
}) -> icc_ls[["lme_rand_slp_symm"]]

# * long format iccs
imap_dfr(icc_ls, function(model_results, model_name) {
    imap_dfr(model_results, function(icc_result, variable_name) {
        data.frame(
            mod_name = model_name,
            var_name = variable_name,
            adj_icc = icc_result$ICC_adjusted, # Adjust based on actual object structure
            unadj_icc = icc_result$ICC_unadjusted, # Adjust based on actual object structure
            stringsAsFactors = FALSE
        )
    })
}) -> icc_df
icc_df

# * icc graph
icc_df %>%
    ggplot2::ggplot(aes(
        x = var_name,
        y = adj_icc,
        fill = mod_name,
        group = mod_name,
        color = mod_name
    )) +
    # ggplot2::geom_col(position = "dodge")
    ggplot2::geom_point() +
    ggplot2::geom_segment(aes(x = var_name, xend = var_name, y = 0, yend = adj_icc))

# # // wide format
# map_dfr(names(icc_ls$lme_fix_slp_un), function(var_name) {
#     data.frame(
#         variable = var_name,
#         fix_slp_adjusted = icc_ls$lme_fix_slp_un[[var_name]]$ICC_adjusted,
#         fix_slp_unadjusted = icc_ls$lme_fix_slp_un[[var_name]]$ICC_unadjusted,
#         rand_slp_adjusted = icc_ls$lme_rand_slp_ar1[[var_name]]$ICC_adjusted,
#         rand_slp_unadjusted = icc_ls$lme_rand_slp_ar1[[var_name]]$ICC_unadjusted,
#         stringsAsFactors = FALSE
#     )
# })

# * output summary table
# sjPlot::tab_model(mod_fit_ls$null$lme_fix_slp_un$turnover_int)
lapply(set_names(var_name_ls$lvl_1_scale_scores), function(.x) {
    modelsummary::modelsummary(
        list(
            mod_fit_ls$null$lme_fix_slp_un[[.x]],
            mod_fit_ls$null$lme_fix_slp_ar1[[.x]],
            mod_fit_ls$null$lme_fix_slp_symm[[.x]]
        ),
        output = "tinytable"
    )
})

anova(
    mod_fit_ls$null$lme_fix_slp_un$turnover_int,
    mod_fit_ls$null$lme_fix_slp_ar1$turnover_int,
    mod_fit_ls$null$lme_fix_slp_symm$turnover_int
)

nlme::lme(
    turnover_int ~ time + burn_pf_pmc + burn_cw_pmc + burn_ee_pmc +
        nf_comp_pmc + nf_auto_pmc + nf_rel_pmc + n_meetings_pmc +
        burn_pf_grp_mean + burn_cw_grp_mean + burn_ee_grp_mean +
        nf_comp_grp_mean + nf_auto_grp_mean + nf_rel_grp_mean + n_meetings_grp_mean,
    random = ~ 1 | id,
    correlation = NULL,
    # correlation = corAR1(form = ~ 1 | id),
    method = "ML",
    data = dat,
    control = lmeControl(
        maxIter = 1000,
        msMaxIter = 1000,
        tolerance = 1e-6,
        niterEM = 50,
        opt = "nlminb",
        # optimMethod = "L-BFGS-B"
    )
) -> x
summary(x)
