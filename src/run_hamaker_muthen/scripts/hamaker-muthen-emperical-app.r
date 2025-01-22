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
library(here)

here::i_am("src/run_hamaker_muthen/scripts/hamaker-muthen-emperical-app.r")

# set up R config
config_path <- here::here("src/run_hamaker_muthen/configs/maker-muthen-emperical-app.yaml")
config <- config::get(file = config_path)
print(config)

# load data
dat <- readr::read_csv(
    file = here::here(config["data_dir"], "Bringmann1.dat"),
    col_names = FALSE,
    col_select = -1,
    skip = 1
) %>%
    dplyr::rename_with(function(x) config[["col_names"]]) %>%
    dplyr::mutate(neurotic_scaled = neurotic / 10) %>%
    dplyr::group_by(id) %>%
    dplyr::mutate(
        pleasant_between = mean(pleasant, na.rm = TRUE),
        pleasant_within = pleasant - pleasant_between
    ) %>%
    dplyr::ungroup() %>%
    dplyr::select(
        id,
        day_num,
        beep_num,
        informat04,
        st_period,
        cheerful,
        starts_with("pleasant"),
        worry,
        fearful,
        somber,
        relaxed,
        starts_with("neurotic")
    )

# readr::problems(dat)
dplyr::glimpse(dat)

# null/empty model for somber
mod_0_somber <- lmerTest::lmer(
    formula = somber ~ 1 + (1 | id),
    data = dat,
    REML = FALSE
)
performance::check_model(mod_0_somber)
parameters::model_parameters(mod_0_somber, effects = "fixed", ci_method = "satterthwaite", group_level = FALSE)
performance::icc(mod_0_somber)
performance::model_performance(mod_0_somber, estimator = "ML")

# null/empty model for pleasant
mod_0_pleasant <- lmerTest::lmer(
    formula = pleasant ~ 1 + (1 | id),
    data = dat,
    REML = FALSE
)
performance::check_model(mod_0_pleasant)
parameters::model_parameters(mod_0_pleasant, effects = "fixed", ci_method = "satterthwaite", group_level = FALSE)
performance::icc(mod_0_pleasant)
performance::model_performance(mod_0_pleasant, estimator = "ML")

# example model
mod_1 <- lmerTest::lmer(
    formula = somber ~ pleasant_within + pleasant_between + neurotic_scaled +
        (1 + pleasant_within | id),
    data = dat,
    REML = FALSE
)
performance::check_model(mod_1)
parameters::model_parameters(
    mod_1,
    effects = "all",
    ci_method = "satterthwaite",
    group_level = FALSE
)

parameters::model_parameters(
    mod_1,
    effects = "all",
    ci_method = "satterthwaite",
    group_level = FALSE,
    standardize = "refit"
)
performance::icc(mod_1)
performance::model_performance(mod_1, estimator = "ML")

performance::compare_performance(
    mod_0_pleasant,
    mod_0_somber,
    mod_1,
    metrics = "all",
    rank = TRUE
)

# compare_parameters(mod_0_somber, mod_0_pleasant, mod_1)
