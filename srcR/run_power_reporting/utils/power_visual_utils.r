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
    # geom_ribbon(
    #     aes(ymin = Lower_CI, ymax = Upper_CI, fill = Effect),
    #     alpha = 0.2,
    #     color = NA
    # ) +
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
