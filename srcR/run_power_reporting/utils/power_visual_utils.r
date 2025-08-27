#!/usr/bin/env Rscript

# import packages
library(ggplot2)
library(here)
library(dplyr) # masks stats::filter, lag; base::intersect, setdiff, setequal, union
library(readr)
library(skimr)

sim_odds <- readr::read_csv(
    file = here::here("srcR/run_power_analysis/data/power_analysis_results_20250801_123346.csv")
)

sim_evens <- readr::read_csv(
    file = here::here("srcR/run_power_analysis/data/power_analysis_results_20250805_143050.csv")
)

# combine the two datasets
power_results <- dplyr::bind_rows(sim_odds, sim_evens)
dplyr::glimpse(power_results)
skimr::skim(power_results)


l1_eff <- 0.1
l2_eff <- 0.30
x_eff <- 0.30
icc <- 0.30
rs_eff <- 0.09

# plot power curves
power_results |>
    dplyr::filter(
        Level1_Effect_Std == l1_eff &
            Level2_Effect_Std == l2_eff &
            XLevel_Intxn_Effect_Std == x_eff &
            ICC == icc &
            Random_Slope_Std == rs_eff
    ) |>
    ggplot2::ggplot(aes(x = N_Level2, y = Power, color = Effect)) +
    geom_line(linewidth = 1) +
    geom_ribbon(
        aes(ymin = Lower_CI, ymax = Upper_CI, fill = Effect),
        alpha = 0.2,
        color = NA
    ) +
    geom_errorbar(aes(ymin = Lower_CI, ymax = Upper_CI),
        width = 20, alpha = 0.6
    ) +
    geom_point(size = 2) +
    geom_hline(yintercept = 0.80, linetype = "dashed", alpha = 0.5) +
    geom_hline(yintercept = 0.90, linetype = "dashed", alpha = 0.5) +
    labs(
        title = "Power Analysis: Sample Size Effects",
        x = "Level 2 Sample Size (n_lvl2)",
        y = "Statistical Power",
        color = "Effect Type"
    ) +
    theme_minimal() +
    ylim(0, 1) +
    scale_x_continuous(
        limits = c(0, max(power_results$N_Level2)),
        breaks = seq(min(power_results$N_Level2), max(power_results$N_Level2), by = 100)
    )


# library(tidyverse)
# library(lme4)
# library(MASS)

# # Function to simulate multilevel data with specified slope-intercept covariance
# simulate_multilevel_data <- function(n_groups = 50, n_per_group = 10,
#                                      tau_00 = 1.0, tau_11 = 0.25, tau_10 = 0) {
#     # Create covariance matrix for random effects
#     Tau <- matrix(c(
#         tau_00, tau_10,
#         tau_10, tau_11
#     ), nrow = 2)

#     # Generate random effects
#     random_effects <- mvrnorm(n_groups, mu = c(0, 0), Sigma = Tau)

#     # Create data structure
#     data <- expand_grid(
#         group = 1:n_groups,
#         individual = 1:n_per_group
#     ) %>%
#         mutate(
#             x = rnorm(n(), 0, 1), # Level-1 predictor
#             u_0j = random_effects[group, 1], # Random intercept
#             u_1j = random_effects[group, 2], # Random slope
#             y = 2.0 + u_0j + (0.5 + u_1j) * x + rnorm(n(), 0, 1) # Outcome
#         )

#     return(list(
#         data = data, true_covariance = tau_10,
#         correlation = tau_10 / sqrt(tau_00 * tau_11)
#     ))
# }

# # Demonstrate three covariance scenarios
# scenarios <- list(
#     "Positive Covariance" = simulate_multilevel_data(tau_10 = 0.3),
#     "Zero Covariance" = simulate_multilevel_data(tau_10 = 0.0),
#     "Negative Covariance" = simulate_multilevel_data(tau_10 = -0.3)
# )

# # Visualize the patterns
# plot_data <- map_dfr(scenarios, ~ {
#     .x$data %>%
#         group_by(group) %>%
#         summarise(
#             intercept = unique(u_0j),
#             slope = unique(u_1j),
#             .groups = "drop"
#         )
# }, .id = "scenario")

# plot_data %>%
#     ggplot(aes(x = slope, y = intercept)) +
#     geom_point(alpha = 0.6) +
#     geom_smooth(method = "lm", se = TRUE) +
#     facet_wrap(~scenario) +
#     labs(
#         title = "Slope-Intercept Relationships Across Scenarios",
#         x = "Random Slope (U₁ⱼ)",
#         y = "Random Intercept (U₀ⱼ)"
#     ) +
#     theme_minimal()
