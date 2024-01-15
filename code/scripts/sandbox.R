library(brms)
library(ggmcmc)
library(ggridges)
library(tidyverse)
library(ggplot2)

# Set seed for reproducibility
set.seed(123)

# Define the number of individuals, time points, and levels
n_individuals <- 1500
n_time_points <- 3
# n_levels <- 2

# Create data frame for the simulation
data_sim <- expand.grid(
  id = seq_len(n_individuals),
  time = seq_len(n_time_points)
#   level = seq_len(n_levels)
)

# Generate independent variables with positive intercorrelations
aut <- rnorm(n_individuals, mean = 0, sd = 1)
com <- 0.5 * aut + rnorm(n_individuals, mean = 0, sd = 1)
rel <- -0.2 * aut + 0.8 * com + rnorm(n_individuals, mean = 0, sd = 1)

# Add independent variables to the data frame
data_sim$aut <- rep(aut, each = n_time_points) #* n_levels)
data_sim$com <- rep(com, each = n_time_points) #* n_levels)
data_sim$rel <- rep(rel, each = n_time_points) #* n_levels)

# Generate dependent variable with differential prediction
# Adjust coefficients as needed for your specific scenario
data_sim$dv <- rnorm(n_individuals * n_time_points,
                     mean = 1 + 0.5 * aut - 0.3 * com + 0.2 * rel,
                     sd = 1)


ggplot2::ggplot(data = data_sim, aes(y = dv, x = aut)) + 
    ggplot2::geom_point(position = "jitter")
    # ggplot2::theme_minimal()


library(ggplot2)
# Specify priors for the brm model
priors <- c(
  prior(normal(0, 1), class = "b", coef = "Intercept"),
  prior(normal(0, 1), class = "b", coef = "aut"),
  prior(normal(0, 1), class = "b", coef = "com"),
  prior(normal(0, 1), class = "b", coef = "rel"),
  prior(normal(0, 1), class = "sd", group = "id"),
  prior(normal(0, 1), class = "sd", group = "time"),
  prior(normal(0, 1), class = "cor", group = "id")
)

# Fit the brm model
mod0 <- brm(
    dv ~ 1 + (1 | id),
    data = data_sim,
    family = gaussian(),
    prior = NULL,
    chains = 4,        # Number of chains
    iter = 5000,       # Number of iterations
    warmup = 2500,     # Number of warmup iterations
    cores = 10,         # Number of cores
    control = list(adapt_delta = 0.99)
    )

mod1 <- brm(
    dv ~ 1 + aut + com + rel + (1 | id),
    data = data_sim,
    family = gaussian(),
    prior = NULL,
    chains = 4,        # Number of chains
    iter = 5000,       # Number of iterations
    warmup = 2500,     # Number of warmup iterations
    cores = 10,         # Number of cores
    control = list(adapt_delta = 0.99)
    )

# Display model summary
summary(mod0)
summary(mod1)
ggs
interceptonlymodeltest <- brm(popular ~ 1 + (1 | class), 
                              data   = popular2data, 
                              warmup = 100, 
                              iter   = 200, 
                              chains = 2, 
                              inits  = "random",
                              cores  = 2)  #the cores function tells STAN to make use of 2 CPU cores simultaneously instead of just 1.
