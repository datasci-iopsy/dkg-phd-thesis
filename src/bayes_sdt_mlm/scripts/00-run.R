# Load required libraries
library(lmerTest)
library(brms)
library(dplyr)
library(readr)
here::i_am("src/bayes_sdt_mlm/scripts/00-run.R")
library(here)
here::here()
getwd()

# Set seed for reproducibility
set.seed(123)

# Number of individuals
n_individuals <- 500

# Number of time points
n_timepoints <- 3

# Generate data for three independent variables
independent_var1 <- sample(1:5, n_individuals * n_timepoints, replace = TRUE)
independent_var2 <- sample(1:5, n_individuals * n_timepoints, replace = TRUE)
independent_var3 <- sample(1:5, n_individuals * n_timepoints, replace = TRUE)

# Generate dependent variable
dependent_var <- 3.11 + 0.3 * independent_var1 + 0.4 * independent_var2 + 0.5 * independent_var3 + rnorm(n_individuals * n_timepoints, mean = 3.26, sd = 0.76)

# Reshape data for longitudinal structure
data <- data.frame(
    Time = rep(1:n_timepoints, each = n_individuals),
    Individual = rep(1:n_individuals, times = n_timepoints),
    Independent_Var1 = independent_var1,
    Independent_Var2 = independent_var2,
    Independent_Var3 = independent_var3,
    Dependent_Var = dependent_var
)

# Check the correlation matrix
cor(data[, c("Independent_Var1", "Independent_Var2", "Independent_Var3", "Dependent_Var")])

# Save data to CSV
readr::write_csv(
    data, 
    "src/data/raw/multilevel_data.csv"
    )

# intercepts-only model
lm(dependent_var ~ 1, data = data) -> mod0_lmer
brms::brm(dependent_var ~ 1, data = data) -> mod0_brm

summary(mod0_lmer)
summary(mod0_brm)

broom.mixed::tidy(mod0_lmer)
broom.mixed::tidy(mod0_brm)

performance::icc(mod0_lmer)
performance::icc(mod0_brm)

lmerTest::lmer(eng ~ 1 + comp + auto + rel + (1 + time_pt | emp_id), data = final_dat) -> mod1_lmer
brms::brm(depress ~ 1 + comp + auto + rel + (1 + time_pt | emp_id), data = final_dat, control = list(adapt_delta = .95)) -> mod1_brm

summary(mod1_lmer)
summary(mod1_brm)

broom.mixed::tidy(mod1_lmer)
broom.mixed::tidy(mod0_brm)

performance::icc(mod0_lmer)
performance::icc(mod0_brm)

simstudy::addColumns(resp_def, long_dat) %>% 
    tibble::as_tibble() %>% 
    ggplot2::ggplot(aes(x = auto, y = burn)) +
    ggplot2::geom_point(aes(group = emp_id)) + 
    ggplot2::geom_smooth(method = "lm", aes(colour = factor(time_pt), group = factor(time_pt)))
# ggplot2::facet_wrap(vars(time_pt))

