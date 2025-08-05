#!/usr/bin/env Rscript

# import packages
library(ggplot2)
library(here)
library(dplyr) # masks stats::filter, lag; base::intersect, setdiff, setequal, union
library(readr)
library(skimr)

power_results <- readr::read_csv(
    file = here::here("srcR/run_power_analysis/data/power_analysis_results_20250801_123346.csv")
)
dplyr::glimpse(power_results)
skimr::skim(power_results)


# plot power curves
power_results |>
    dplyr::filter(
        Level1_Effect_Std == 0.30 &
            Level2_Effect_Std == 0.30 &
            XLevel_Intxn_Effect_Std == 0.30 &
            ICC == 0.30 &
            Random_Slope_Std == 0.09
    ) |>
    ggplot2::ggplot(aes(x = N_Level2, y = Power, color = Effect)) +
    geom_line(linewidth = 1) +
    geom_point(size = 2) +
    geom_hline(yintercept = 0.8, linetype = "dashed", alpha = 0.5) +
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
# facet_wrap(~ Level2_Effect_Std + XLevel_Intxn_Effect_Std, nrow = 3, ncol = 3)
