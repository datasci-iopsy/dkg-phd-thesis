library(easystats)
# library(ggeffects) # masks modelbased::pool_predicts; easystats::install_latest
library(glmmTMB) # todo: determine if necessary; https://glmmtmb.r-universe.dev/glmmTMB
library(modelsummary)
library(lme4) # masks tidyr::expand, pack, unpack
library(lmerTest) # masks lme4::lmer; stats::step
# library(marginaleffects)
library(sjPlot)
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


# quick viz
ggplot2::ggplot(data = dat, aes(x = occasion, y = anti, group = id)) +
    geom_line() +
    geom_smooth(
        aes(group = kidgen, color = kidgen),
        method = "lm", se = FALSE, linewidth = 1
    ) -> p1

ggplot2::ggplot(data = dat, aes(x = occasion, y = read, group = id)) +
    geom_line() +
    geom_smooth(
        aes(group = kidgen, color = kidgen),
        method = "lm", se = FALSE, linewidth = 1
    ) -> p2

patchwork::wrap_plots(p1, p2)

# * mixed modeling
list() -> mod_ls # list to hold models

# null/empty models
lmerTest::lmer(anti ~ 1 + (1 | id), data = dat, REML = FALSE) -> mod_null_anti
lmerTest::lmer(read ~ 1 + (1 | id), data = dat, REML = FALSE) -> mod_null_read


# # todo: determine if specified cor structure is necessary
# glmmTMB::glmmTMB(anti ~ 1 + (1 | id), data = dat, family = gaussian(), REML = FALSE)
# specify cor structure:
# review: https://padme.arising.com.au:3004/node-repository/CRAN/web/packages/glmmTMB/vignettes/covstruct.html
# review: https://glmmtmb.r-universe.dev/articles/glmmTMB/covstruct.html
# glmmTMB::glmmTMB(anti ~ 1 + (1 | id) + ar1(occasion_fct + 0 | id), data = dat, family = gaussian(), REML = FALSE)

# determine if mlm is necessary
purrr::map(list(mod_null_anti, mod_null_read), function(x) {
    performance::icc(x)
}) # 48.1% of variability in anti between ids; 11.1% of variability in read between ids


# random intercepts, fixed slopes
lmerTest::lmer(
    anti ~ occasion + (1 | id),
    data = mod_vars,
    REML = FALSE,
    lmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 2e5))
) -> mod_ls[["ri_fs_time"]]

# random intercepts, random slopes
lmerTest::lmer(
    anti ~ occasion + (1 + occasion | id),
    data = mod_vars,
    REML = FALSE,
    lmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 2e5))
) -> mod_ls[["ri_rs_time"]]

# random intercepts, fixed slopes models but different codings of time; full
lmerTest::lmer(
    anti ~ occasion + read_wpc +
        read_grp_mean + kidgen + momage_gmc + homecog_gmc + homeemo_gmc +
        (1 | id),
    data = dat,
    REML = FALSE,
    lmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 2e5))
) -> mod_ls[["ri_fs_full"]]

# random intercepts, random slopes models but different codings of time; full
lmerTest::lmer(
    anti ~ occasion + read_wpc +
        read_grp_mean + kidgen + momage_gmc + homecog_gmc + homeemo_gmc +
        (1 + occasion | id),
    data = dat,
    REML = FALSE,
    lmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 2e5))
) -> mod_ls[["ri_rs_full"]]

performance::compare_performance(mod_ls)

sjPlot::plot_model(mod_ls$ri_rs_time)
sjPlot::plot_model(mod_ls$ri_rs_full)

sjPlot::tab_model(mod_ls) # p.style = "stars")

purrr::map(mod_ls, function(x) {
    performance::check_model(x)
})

modelsummary::modelsummary(mod_ls$ri_rs_full, output = "tinytable")
anova(mod_ls$ri_rs_time, mod_ls$ri_rs_full)

# https://modelsummary.com
# https://tilburgsciencehub.com/topics/visualization/data-visualization/regression-results/model-summary/
modelsummary::modelsummary(
    list(
        "Null" = mod_0_anti,
        "Fixed Slopes" = mod_randint_fixsl,
        "Random Slopes" = mod_randint_randsl
    ),
    output = "tinytable",
    stars = TRUE,
    estimate = "{estimate}",
    statistic = "{p.value} [{conf.low}, {conf.high}]",
    fmt = 2
)

# https://strengejacke.github.io/sjPlot/articles/tab_mixed.html
sjPlot::tab_model(mod_0_anti, mod_randint_fixsl, mod_randint_randsl, p.style = "stars")
sjPlot::plot_model(mod_randint_randsl)
sjPlot::plot_model(mod_randint_randsl, type = "pred", terms = c("occasion_gmc [all]", "kidgen"))

# broom.mixed::tidy(mod_randint_randsl)

purrr::map(
    list(
        "null" = mod_0_anti,
        "random intercepts, fixed slopes" = mod_randint_fixsl,
        "random intercepts, random slopes" = mod_randint_randsl
    ), function(x) {
        performance::check_model(x)
    }
)

performance::compare_performance(
    mod_0_anti,
    glmm_mod_0_anti,
    mod_randint_fixsl,
    mod_randint_randsl,
    metrics = "all"
    # rank = TRUE
)

mod <- mod_randint_randsl
# # 1. Predicted antisocial behavior across occasions
# pred_time <- predict_response(mod, terms = "occasion [all]")

# # 2. Predicted effects of emotional support (homeemo)
# pred_emo <- predict_response(mod, terms = "homeemo_between")

# # 3. Predicted occasion effect by child gender
# pred_time_gender <- predict_response(mod, terms = c("occasion [all]", "kidgen"))

# p1 <- plot(pred_time) +
#     labs(x = "Measurement Occasion", y = "Predicted Antisocial Score")

# p2 <- plot(pred_emo) +
#     labs(x = "Emotional Support", y = "Predicted Antisocial Score")

# p3 <- plot(pred_time_gender) +
#     labs(x = "Occasion", colour = "Gender") +
#     ggtitle("Occasion Effect by Gender")

# p1 + p2 + p3

# Estimate random intercepts and slopes by child
re <- estimate_grouplevel(mod)

# View first rows
head(re)

kidgen_means <- modelbased::estimate_means(mod, by = "kidgen")
plot(kidgen_means)

ggplot(dat, aes(x = kidgen, y = anti)) +
    # Add base data
    geom_violin(aes(fill = kidgen), color = "white") +
    geom_jitter(width = 0.1, height = 0, alpha = 0.5, size = 3) +
    # Add pointrange and line for means
    geom_line(data = kidgen_means, aes(y = Mean, group = 1), linewidth = 1) +
    geom_pointrange(
        data = kidgen_means,
        aes(y = Mean, ymin = CI_low, ymax = CI_high),
        size = 1,
        color = "white"
    ) +
    # Improve colors
    scale_fill_manual(values = c("pink", "lightblue")) +
    theme_minimal()


# kidgen_contrasts <- estimate_contrasts(mod, contrast = "kidgen")
# kidgen_contrasts
# plot(kidgen_contrasts, kidgen_means)


# modelbased::estimate_expectation(mod) %>% glimpse()

# preds <- dat  %>%
# tidyr::drop_na()  %>%
# bind_cols(modelbased::estimate_expectation(mod))

# # preds pred_ri_fs <- modelbased::estimate_expectation(mod) %>%
# #     dplyr::bind_cols(filter(!is.na(dat, anti)))

# dat %>% dplyr::filter(across(all_of(names(.), !is.na()))
# # pred_ri_rs <- modelbased::estimate_expectation(mod)

# Plot group-level effects
ggplot2::ggplot(re, aes(x = Level, y = Coefficient, colour = Parameter)) +
    geom_point() +
    # geom_errorbar(aes(ymin = `95% CI low`, ymax = `95% CI high`), width = 0.2) +
    facet_wrap(~Parameter, scales = "free_y") +
    labs(
        x = "Child ID", y = "Deviation from Fixed Effect",
        title = "Random Intercepts and Slopes by Child"
    )
