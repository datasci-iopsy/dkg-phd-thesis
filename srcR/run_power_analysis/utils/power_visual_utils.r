#!/usr/bin/env Rscript
# Plot power curves
library(ggplot2)
power_results |>
    dplyr::filter(
        Level1_Effect_Std == 0.3 &
            Level2_Effect_Std == 0.3 &
            XLevel_Intxn_Effect_Std == 0.3 &
            ICC == 0.3 &
            Random_Slope_Std == 0.25
    ) |>
    ggplot(aes(x = N_Level2, y = Power, color = Effect)) +
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
    scale_x_continuous(limits = c(0, max(param_grid$n_lvl2)), breaks = param_grid$n_lvl2)
