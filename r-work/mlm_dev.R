library(easystats)
library(haven)
library(here)
library(lme4) # masks tidyr::expand, pack, unpack
library(lmerTest) # masks lme4::lmer; stats::step
library(modelsummary) # masks parameters::supported_models; insight::supported_models
library(patchwork)
library(tidyverse)
library(tinytable)
library(rmcorr)
library(sjPlot)
library(summarytools) # masks tibble::view
# library(glmmTMB) # todo: determine if necessary; https://glmmtmb.r-universe.dev/glmmTMB
# library(ggeffects) # masks modelbased::pool_predicts; easystats::install_latest
# library(marginaleffects)

# options for script
options(tibble.width = Inf)

# proj root; build paths from here ;)
here::here()

# * data load & prep
haven::read_sav(file = here::here("CurranLong.sav")) %>%
    tibble::tibble() %>%
    dplyr::mutate(
        id = as.character(id),
        kidgen = factor(if_else(kidgen == 0, "Female", "Male"))
        # occasion_fct = factor(occasion) # // necessary for glmmTMB
    ) %>%
    # create person/group means; review centering by Lesa Hoffman:
    # https://www.lesahoffman.com/PSYC944/944_Lecture09_TVPredictors_Fluctuation.pdf
    dplyr::group_by(id) %>%
    dplyr::mutate(
        # group means
        momage_grp_mean = mean(momage, na.rm = TRUE),
        kidage_grp_mean = mean(kidage, na.rm = TRUE),
        homecog_grp_mean = mean(homecog, na.rm = TRUE),
        homeemo_grp_mean = mean(homeemo, na.rm = TRUE),
        # occasion_grp_mean = mean(occasion, na.rm = TRUE),
        anti_grp_mean = mean(anti, na.rm = TRUE),
        read_grp_mean = mean(read, na.rm = TRUE),
        kidagetv_grp_mean = mean(kidagetv, na.rm = TRUE),

        # group mean centering
        # occasion_wpc = occasion - occasion_grp_mean,
        kidagetv_wpc = kidagetv - kidagetv_grp_mean,
        read_wpc = read - read_grp_mean
    ) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(
        # grand mean centering
        occasion_gmc = occasion - mean(occasion, na.rm = TRUE),
        momage_gmc = momage - mean(momage, na.rm = TRUE),
        homecog_gmc = homecog - mean(homecog, na.rm = TRUE),
        homeemo_gmc = homeemo - mean(homeemo, na.rm = TRUE)
    ) -> dat

# write data to file
readr::write_csv(dat, file = here::here("CurranLong_clean.csv"))

# quick views of data
dplyr::glimpse(dat)
modelsummary::datasummary_skim(dat)

# # add'l data exploration views of data
# dat %>%
#     dplyr::select(!id) %>%
#     summarytools::dfSummary() %>%
#     summarytools::stview()

# dat %>%
#     dplyr::select(!id) %>%
#     summarytools::descr() %>%
#     summarytools::stview()

# dat %>%
#     dplyr::select(where(is.factor)) %>%
#     summarytools::freq() %>%
#     summarytools::stview()

# extract variables used in study (sans transformations)
dat %>%
    dplyr::select(
        id,
        occasion,
        momage,
        homecog,
        homeemo,
        kidagetv,
        anti,
        read
    ) -> init_vars

# review correlations
dat %>%
    dplyr::select(
        momage_gmc,
        homecog_gmc,
        homeemo_gmc,
        occasion,
        anti,
        read
    )
modelsummary::datasummary_correlation(init_vars[, -1]) # occasion & kidagetv r = .96 or 92% shared variance

# ! repeated measures violate the independence assumption; try alt approach
init_vars %>%
    dplyr::select(occasion, anti, read, kidagetv) -> rmcorr_vars

print(round(rmcorr_mat, 3))
rmcorr::rmcorr_mat(
    participant = init_vars$id,
    variables = c(
        # "momage",
        # "homecog",
        # "homeemo",
        "occasion",
        "anti",
        "read",
        "kidagetv"
    ),
    dataset = init_vars,
    CI.level = 0.95
) -> rmc_mat
rmc_mat

map(rmc_mat$models, function(x) {
    plot(x)
})

# extract variables of interest
dat %>%
    dplyr::select(
        id,
        occasion,
        kidgen,
        momage_gmc,
        homecog_gmc,
        homeemo_gmc,
        read_grp_mean,
        read_wpc,
        anti
    ) -> mod_vars

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


# !!!!!!!








# # # Create a simulated dataset based on your design
# # load(url("https://github.com/m-clark/mixed-models-with-R/raw/master/data/gpa.RData?raw=true"))
# # head(gpa)
# # summary(gpa)
# # set.seed(123)  # For reproducibility

# # summary(mod_0_anti)
# # summary(mixed_2a)
# # performance::compare_performance(mod_0_anti, mod_0_read, mod_ri_fs_01, mod_ri_rs_01)

# # parameters::parameters(model = mixed_2a)
# # summary(mixed_2a)
# # performance::model_performance(mixed_2a)

# # performance::icc(mixed_null)
# # summary(mixed_init)

# # # Define parameters
# # n_subjects <- 500 # Number of subjects
# # n_timepoints <- 3 # Number of timepoints per subject
# # effect_size <- 0.4 # Medium effect size
# # sigma_subject <- 1.0 # Between-subject standard deviation
# # sigma_error <- 1.0 # Within-subject standard deviation

# # # Create data frame
# # subject_id <- rep(1:n_subjects, each = n_timepoints)
# # time <- rep(0:(n_timepoints - 1), times = n_subjects)
# # df <- data.frame(subject_id = factor(subject_id), time = time)

# # # Simulate random effects
# # b0 <- rnorm(n_subjects, 2.4, sigma_subject) # Random intercepts
# # b1 <- rnorm(n_subjects, 0, sigma_subject * 0.2) # Random slopes

# # # Calculate expected values and add noise
# # df$y <- rep(b0, each = n_timepoints) + time * effect_size + rep(b1, each = n_timepoints) * time + rnorm(n_subjects * n_timepoints, 0, sigma_error)

# # # Fit the model
# # model <- lmer(y ~ time + (1 + time | subject_id), data = df)
# # summary(model)

# # # Perform power analysis
# # # For the fixed effect of time
# # time_power <- powerSim(model, nsim = 200, test = fixed("time"))
# # print(time_power)

# # # Create a power curve for different sample sizes
# # pc <- powerCurve(model, along = "subject_id", breaks = c(10, 20, 30, 40, 50, 60, 70, 80), nsim = 100)
# # plot(pc)

# # # You can also extend the model to test different effect sizes
# # model_small <- model
# # fixef(model_small)["time"] <- 0.2 # Set to small effect size
# # power_small <- powerSim(model_small, nsim = 200, test = fixed("time"))
# # print(power_small)

# # model_large <- model
# # fixef(model_large)["time"] <- 0.6 # Set to large effect size
# # power_large <- powerSim(model_large, nsim = 200, test = fixed("time"))
# # print(power_large)
