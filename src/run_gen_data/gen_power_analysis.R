library(simr)
library(lme4)

# Simulate data
set.seed(123)

num_subjects <- 50
num_timepoints <- 5

subject <- factor(rep(1:num_subjects, each=num_timepoints))
time <- factor(rep(1:num_timepoints, num_subjects))
IV1 <- rnorm(num_subjects * num_timepoints)
IV2 <- rnorm(num_subjects * num_timepoints)
IV3 <- rnorm(num_subjects * num_timepoints)
DV <- 1 + 0.5 * IV1 + 0.3 * IV2 + 0.2 * IV3 + rnorm(num_subjects * num_timepoints, sd=0.5) + rnorm(num_subjects, sd=0.5)[subject]

data <- data.frame(subject, time, IV1, IV2, IV3, DV)

# Fit the mixed model
model <- lmer(DV ~ IV1 + IV2 + IV3 + (1 | subject), data=data)
summary(model)

# Convert the fitted model to a 'simr' model
power_model <- extend(model, along="subject", n=num_subjects)

# Define the number of simulations
num_simulations <- 1000

# Power analysis for IV1
power_IV1 <- powerSim(power_model, test = fixed("IV1", "t"), nsim = num_simulations)
print(power_IV1)

# Power analysis for IV2
power_IV2 <- powerSim(power_model, test = fixed("IV2", "t"), nsim = num_simulations)
print(power_IV2)

# Power analysis for IV3
power_IV3 <- powerSim(power_model, test = fixed("IV3", "t"), nsim = num_simulations)
print(power_IV3)