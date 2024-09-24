# Load necessary libraries
library(simr) # masks lme4::getData
library(lme4)
library(MASS)
library(dplyr) # masks MASS::select; stats::filter, lag; base::intersect, setdiff, setequal, union

# Function to generate correlated data for independent variables
generate_correlated_data <- function(n_subjects, n_repeats, corr_matrix, means, sds) {
    # Generate multivariate normal data
    mvrnorm_data <- MASS::mvrnorm(n = n_subjects * n_repeats, mu = means, Sigma = corr_matrix)

    # Convert to a data frame and give appropriate column names
    df <- as.data.frame(mvrnorm_data)
    colnames(df) <- c("IV1", "IV2", "IV3")

    # Create subject and repeat IDs
    df$Subject <- rep(1:n_subjects, each = n_repeats)
    df$Repeat <- rep(1:n_repeats, times = n_subjects)

    return(df)
}

# Function to simulate a response variable (DV) based on IVs
simulate_response <- function(data, coefs, random_effect_sd) {
    # Fixed effects linear combination (DV = beta0 + beta1*IV1 + beta2*IV2 + beta3*IV3 + error)
    data$DV <- coefs[1] + coefs[2] * data$IV1 + coefs[3] * data$IV2 + coefs[4] * data$IV3

    # Add random intercept for subjects (random effect)
    random_intercepts <- rnorm(length(unique(data$Subject)), mean = 0, sd = random_effect_sd)
    data$DV <- data$DV + random_intercepts[data$Subject]

    # Add normally distributed error
    data$DV <- data$DV + rnorm(nrow(data), mean = 0, sd = 1)

    return(data)
}

# Function to fit mixed model and perform power analysis
run_power_analysis <- function(data, effect_size, n_sim = 1000, alpha = 0.05) {
    # Fit a mixed model
    model <- lmer(DV ~ IV1 + IV2 + IV3 + (1 | Subject), data = data)

    # Scale the effect size
    fixef(model)["IV1"] <- effect_size

    # Set up the power simulation
    power_sim <- powerSim(model, nsim = n_sim, alpha = alpha)

    return(power_sim)
}

# Comprehensive function to run everything
run_simulation <- function(
    n_subjects = 500, n_repeats = 3, corr_matrix, means = c(0, 0, 0),
    sds = c(1, 1, 1), coefs = c(0, 0.5, 0.5, 0.5), random_effect_sd = 1,
    effect_size = 0.5, n_sim = 5000, alpha = 0.05) {
    # Step 1: Generate correlated data
    data <- generate_correlated_data(n_subjects, n_repeats, corr_matrix, means, sds)

    # Step 2: Simulate the response variable
    data <- simulate_response(data, coefs, random_effect_sd)

    # Step 3: Run power analysis
    power_sim <- run_power_analysis(data, effect_size, n_sim, alpha)

    # Print power results
    print(summary(power_sim))
}

# Example of running the comprehensive simulation
# Define the correlation matrix for IVs
correlation_matrix <- matrix(
    c(
        1, 0.3, 0.3,
        0.3, 1, 0.3,
        0.3, 0.3, 1
    ),
    nrow = 3, byrow = TRUE
)

# Running the simulation with default parameters
run_simulation(corr_matrix = correlation_matrix)
