library(MASS)
library(tidyverse)
library(DataExplorer)
library(rmcorr)
library(lme4) # masks tidyr::expand, pack, unpack
library(lmerTest) # masks lme4::lmer; stats::step
library(performance)
library(parameters)
library(merDeriv)
library(see)

here::i_am("src/run_gen_data/scripts/liebenberg-et-al-2022-syn-data.R")
library(here)

# set seed for reproducibility
set.seed(19910113)

# parameters
n <- 750 # num of individuals
time <- 3 # num of timepoints
total_obs <- n * time
# id <- gl(n = n, k = time, labels = )
# control variables (time-invariant)
age <- round(rnorm(n, mean = 43.2, sd = 13.48)) # ~Merz et al., 2013

ethnicity <- forcats::as_factor(sample(
    c("Black", "White", "Asian", "Hispanic", "Other"),
    size = n,
    replace = TRUE,
    prob = c(0.25, 0.5, 0.1, 0.1, 0.05)
))

gender <- forcats::as_factor(sample(
    c("Man", "Woman", "Nonbinary", "Prefer not to say"),
    size = n,
    replace = TRUE,
    prob = c(0.48, 0.48, 0.02, 0.02)
))

org_tenure <- forcats::as_factor(sample(
    c("<1 year", "1-3 years", "3-5 years", ">5 years"),
    size = n,
    replace = TRUE,
    prob = c(0.1, 0.4, 0.3, 0.2)
))

edu_lvl <- forcats::as_factor(sample(
    c("High School", "Associate", "Bachelor's", "Master's", "Doctorate", "Other"),
    size = n,
    replace = TRUE,
    prob = c(0.2, 0.3, 0.3, 0.15, 0.03, 0.02)
))

remote_flag <- sample(
    c(TRUE, FALSE),
    size = n,
    replace = TRUE,
    prob = c(0.4, 0.6)
)

# PANAS variables
pos_affect <- rnorm(n, mean = 19.15, sd = 2.77) # ~Thompson, 2007
neg_affect <- rnorm(n, mean = 12.73, sd = 3.01) # ~Thompson, 2007

df_id_time <- tibble::tibble(
    id = rep(1:n, each = time),
    time = rep(0:(time - 1), times = n)
)

df_controls <- tibble::tibble(
    id = 1:n,
    age = age,
    ethnicity = ethnicity,
    gender = gender,
    org_tenure = org_tenure,
    edu_lvl = edu_lvl,
    remote_flag = remote_flag,
    pos_affect = pos_affect,
    neg_affect = neg_affect
)

# fixed effects ~Liebenberg et al, 2022
fixed_intercept <- 2.4
fixed_slope_autonomy <- 0.31
fixed_slope_competence <- 0.33
fixed_slope_relatedness <- 0.27

# Random effects: Variance components
random_intercept_sd <- sqrt(0.30) # Intercept variance
random_slope_sd <- sqrt(0.05) # Slope variance for autonomy/competence/relatedness

# Residual variance
residual_sd <- sqrt(0.15)

# Generate participant-level random effects
df_random_effects <- tibble(
    id = 1:n,
    random_intercept = rnorm(n, mean = 0, sd = random_intercept_sd),
    random_slope_autonomy = rnorm(n, mean = 0, sd = random_slope_sd),
    random_slope_competence = rnorm(n, mean = 0, sd = random_slope_sd),
    random_slope_relatedness = rnorm(n, mean = 0, sd = random_slope_sd)
)

# # look at the data
# purrr::map(c(df_id_time, df_controls, df_random_effects), function(x) dplyr::glimpse(x))

# build out full data
dat <- df_id_time %>%
    dplyr::left_join(y = df_controls, by = "id") %>%
    dplyr::left_join(df_random_effects, by = "id") %>%
    dplyr::mutate(
        # Simulate predictors (autonomy, competence, relatedness)
        aut = rnorm(total_obs, mean = 3.69, sd = 0.60),
        com = rnorm(total_obs, mean = 3.97, sd = 0.67),
        rel = rnorm(total_obs, mean = 3.07, sd = 0.66),
        # meeting moderators
        meeting_cnt = rpois(n * time, lambda = 1),
        meeting_hrs = rgamma(n * time, shape = 1.5, scale = 0.5),

        # Simulate outcome: Daily work engagement
        eng = fixed_intercept + random_intercept +
            fixed_slope_autonomy * aut +
            fixed_slope_competence * com +
            fixed_slope_relatedness * rel +
            rnorm(total_obs, mean = 0, sd = residual_sd)
    ) %>%
    dplyr::select(!tidyr::starts_with("random")) %>%
    dplyr::group_by(id) %>%
    dplyr::mutate(
        # Within-person centered time-varying predictors
        aut_cw = aut - mean(aut, na.rm = TRUE),
        com_cw = com - mean(com, na.rm = TRUE),
        rel_cw = rel - mean(rel, na.rm = TRUE),
        eng_cw = eng - mean(eng, na.rm = TRUE),
        meeting_cnt_cw = meeting_cnt - mean(meeting_cnt, na.rm = TRUE),
        meeting_hrs_cw = meeting_hrs - mean(meeting_hrs, na.rm = TRUE),

        # Between-person means (for inclusion at between-person level)
        aut_bw = mean(aut, na.rm = TRUE),
        com_bw = mean(com, na.rm = TRUE),
        rel_bw = mean(rel, na.rm = TRUE),
        meeting_cnt_bw = mean(meeting_cnt, na.rm = TRUE),
        meeting_hrs_bw = mean(meeting_hrs, na.rm = TRUE)
    ) %>%
    dplyr::ungroup()


dplyr::glimpse(dat)
summary(dat)



# # generate a report
# DataExplorer::create_report(
#     data = dat,
#     # “default”, “bootstrap”, “cerulean”, “cosmo”, “darkly”, “flatly”, “journal”,
#     # “lumen”, “paper”, “readable”, “sandstone”, “simplex”, “spacelab”, “united”, “yeti”
#     # output_format = html_document(toc = TRUE, toc_depth = 6, theme = "spacelab"),
#     output_file = "liebenberg-et-al-2022.html",
#     output_dir = here::here("src/run_gen_data/reports"),
#     y = NULL,
#     config = configure_report(),
#     report_title = "Data Profiling Report"
# )

mod_0a <- lmerTest::lmer(
    formula = eng ~ 1 + (1 | id),
    data = dat,
    REML = FALSE
)
performance::check_model(mod_0a)
parameters::model_parameters(mod_0a, effects = "fixed", ci_method = "satterthwaite", group_level = TRUE)
performance::icc(mod_0a)
performance::model_performance(mod_0a, estimator = "ML")

# # Warning message:
# # Random slopes not present as fixed effects. This artificially inflates the conditional random effect variances.
# # Solution: Respecify fixed structure!
# mod_0b <- lmerTest::lmer(
#     formula = eng ~ 1 + (time | id),
#     data = dat,
#     REML = FALSE
# )
# performance::check_model(mod_0b)
# parameters::model_parameters(mod_0b, effects = "fixed", ci_method = "satterthwaite", group_level = TRUE)
# performance::icc(mod_0b)
# performance::model_performance(mod_0b, estimator = "ML")

# Random intercept model
mod_1a <- lmerTest::lmer(
    formula = eng ~ time + (1 | id),
    data = dat,
    REML = FALSE
)
performance::check_model(mod_1a)
parameters::model_parameters(mod_1a, effects = "all")
performance::icc(mod_1a)
performance::model_performance(mod_1a, estimator = "ML")
# ggeffects::predict_response(mod_1, terms = c("time")) |> plot(show_data = TRUE)

mod_1b <- lmerTest::lmer(
    formula = eng ~ time + (time | id),
    data = dat,
    REML = FALSE
)
performance::check_model(mod_1b)
parameters::model_parameters(mod_1b)
performance::icc(mod_1b)
performance::model_performance(mod_1b, estimator = "ML")

mod_2a <- lmerTest::lmer(
    formula = eng ~ time + aut_cw + aut_bw +
        com_cw + com_bw + rel_cw + rel_bw +
        meeting_cnt_cw + meeting_cnt_bw +
        meeting_hrs_cw + meeting_hrs_bw + (1 | id),
    data = dat,
    REML = FALSE
)
performance::check_model(mod_2a)
parameters::model_parameters(mod_2a)
performance::icc(mod_2a)
performance::model_performance(mod_2a, estimator = "ML")

mod_2b <- lmerTest::lmer(
    formula = eng ~ time + aut_cw + com_cw + rel_cw + meeting_cnt_cw + meeting_hrs_cw + (time | id),
    data = dat,
    REML = FALSE
)
performance::check_model(mod_2b)
parameters::model_parameters(mod_2b)
performance::icc(mod_2b)
performance::model_performance(mod_2b, estimator = "ML")

# ggeffects::predict_response(mod_2, terms = c("time")) |> plot(show_data = TRUE)

performance::compare_performance(
    mod_0a, mod_1a, mod_1b, mod_2a, mod_2b,
    rank = TRUE,
    metrics = "common"
)

anova(mod_2a, mod_2b)
ggeffects::predict_response(mod_2a)
# performance::check_outliers(mod_0, c("zscore_robust", "mcd", "cook"))
# performance::check_autocorrelation(mod_0)
# performance::model_performance((mod_0))

# # residuals
# sim_residuals <- performance::simulate_residuals(mod_0)
# sim_residuals

# DHARMa::testUniformity(sim_residuals, plot = FALSE)
# performance::check_residuals(sim_residuals)
# performance::check_outliers(sim_residuals)
# performance::check_model(sim_residuals)

# # Random intercept model
# mod_3 <- lmerTest::lmer(
#     formula = eng ~ aut + com + rel + (1 | id),
#     data = dat,
#     REML = FALSE
# )
# performance::check_model(mod_2)
# parameters::model_parameters(mod_2)
# performance::icc(mod_2)
# performance::model_performance((mod_2))

# # Random intercept model
# mod_3 <- lmerTest::lmer(
#     formula = eng ~ time + aut + com + rel + meeting_cnt + meeting_hrs + (1 | id),
#     data = dat,
#     REML = FALSE
# )
# performance::check_model(mod_3)
# parameters::model_parameters(mod_3)
# performance::icc(mod_3)
# performance::model_performance((mod_3))

# # Random intercept model
# mod_3b <- lmerTest::lmer(
#     formula = eng ~ time + aut + com + rel + meeting_cnt + meeting_hrs + (time | id),
#     data = dat,
#     REML = FALSE
# )
# performance::check_model(mod_3b)
# parameters::model_parameters(mod_3b)
# performance::icc(mod_3b)
# performance::model_performance((mod_3b))

# # Random intercept model
# mod_4 <- lmerTest::lmer(
#     formula = eng ~ time + meeting_cnt * aut + meeting_hrs * aut +
#         meeting_cnt * com + meeting_hrs * com +
#         meeting_cnt * rel + meeting_hrs * rel + (1 | id),
#     data = dat,
#     REML = FALSE
# )
# performance::check_model(mod_4)
# parameters::model_parameters(mod_4)
# performance::icc(mod_4)
# performance::model_performance((mod_4))

# # Random intercept model
# mod_4b <- lmerTest::lmer(
#     formula = eng ~ time + meeting_cnt * aut + meeting_hrs * aut +
#         meeting_cnt * com + meeting_hrs * com +
#         meeting_cnt * rel + meeting_hrs * rel + (time | id),
#     data = dat,
#     REML = FALSE
# )
# performance::check_model(mod_4b)
# parameters::model_parameters(mod_4b)
# performance::icc(mod_4b)
# performance::model_performance((mod_4b))

# # Random intercept model
# mod_5 <- lmerTest::lmer(
#     formula = eng ~ time + meeting_cnt * aut + meeting_hrs * aut +
#         meeting_cnt * com + meeting_hrs * com +
#         meeting_cnt * rel + meeting_hrs * rel +
#         age + ethnicity + gender + org_tenure + edu_lvl + remote_flag +
#         pos_affect + neg_affect + (1 | id),
#     data = dat,
#     REML = FALSE
# )
# performance::check_model(mod_5)
# parameters::model_parameters(mod_5)
# performance::icc(mod_5)
# performance::model_performance((mod_5))

# # Random intercept model
# mod_5b <- lmerTest::lmer(
#     formula = eng ~ time + meeting_cnt * aut + meeting_hrs * aut +
#         meeting_cnt * com + meeting_hrs * com +
#         meeting_cnt * rel + meeting_hrs * rel +
#         age + ethnicity + gender + org_tenure + edu_lvl + remote_flag +
#         pos_affect + neg_affect + (time | id),
#     data = dat,
#     REML = FALSE
# )
# performance::check_model(mod_5b)
# parameters::model_parameters(mod_5b)
# performance::icc(mod_5b)
# performance::model_performance((mod_5b))

# # compare models
# performance::compare_performance(
#     mod_0, mod_1, mod_2, mod_3, mod_3b, mod_4, mod_4b, mod_5, mod_5b,
#     rank = TRUE
# )
# plot(performance::compare_performance(
#     mod_0, mod_1, mod_2, mod_3, mod_3b, mod_4, mod_4b, mod_5, mod_5b,
#     rank = TRUE
# ))


# # compare models
# performance::test_performance(
#     mod_0, mod_1, mod_2, mod_3, mod_3b, mod_4, mod_4b, mod_5, mod_5b
# )
