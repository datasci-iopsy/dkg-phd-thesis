#!/usr/bin/env Rscript
# =============================================================================
# analysis/run_power_analysis/scripts/visualize_power_analysis.R
#
# Power curve visualizations for the multilevel model sensitivity analysis.
# Produces publication-quality PDF figures from simulation output (.rds/.csv).
#
# Auto-detects the most recent results file and discovers parameter levels
# from the data, so it scales from a 3-point benchmark to the full 15-point
# production grid without changes.
#
# Output: PDF figures -> analysis/run_power_analysis/figs/
# =============================================================================

# --- [0] Libraries and setup ------------------------------------------------
library(ggplot2)
library(patchwork)
library(scales)
library(RColorBrewer)
library(dplyr)
library(tidyr)
library(readr)
library(here)
library(glue)
library(stringr)

options(tibble.width = Inf)

# Source shared utilities (log_msg, ensure_dir)
source(here::here("analysis", "shared", "utils", "common_utils.r"))

# --- Global settings ---------------------------------------------------------
FIGS_DIR <- here::here("analysis", "run_power_analysis", "figs")
DATA_DIR <- here::here("analysis", "run_power_analysis", "data")
ensure_dir(FIGS_DIR)

POWER_THRESHOLD <- 0.80

# Clean theme: white background, light grid, no clutter
theme_power <- theme_bw(base_size = 12, base_family = "serif") +
    theme(
        panel.grid.minor   = element_blank(),
        panel.grid.major.x = element_blank(),
        panel.grid.major.y = element_line(color = "grey90", linewidth = 0.3),
        strip.background   = element_rect(fill = "grey95", color = "grey70"),
        strip.text         = element_text(face = "bold", size = 10),
        plot.title         = element_text(face = "bold", size = 13, hjust = 0),
        plot.subtitle      = element_text(size = 10, hjust = 0, color = "grey40"),
        legend.position    = "bottom",
        legend.title       = element_text(face = "bold", size = 10),
        legend.key.width   = unit(1.5, "cm"),
        plot.margin        = margin(10, 15, 10, 15)
    )
theme_set(theme_power)

# Color palettes — hand-picked for max distinction
pal_3 <- c("#E41A1C", "#377EB8", "#4DAF4A")   # red, blue, green (Brewer Set1)
pal_3_dark <- c("#1B9E77", "#D95F02", "#7570B3") # teal, orange, purple (Brewer Dark2)

# PDF save helper
save_pdf <- function(plot, filename, width = 10, height = 7) {
    filepath <- file.path(FIGS_DIR, filename)
    ggsave(filepath,
        plot = plot, device = "pdf",
        width = width, height = height, dpi = 300
    )
    log_msg("Saved: ", filepath)
}


# --- [1] Data loading -------------------------------------------------------
log_msg("Phase 1: Loading power analysis results")

rds_files <- sort(list.files(DATA_DIR,
    pattern = "^power_analysis_results_.*\\.rds$",
    full.names = TRUE
))
csv_files <- sort(list.files(DATA_DIR,
    pattern = "^power_analysis_results_.*\\.csv$",
    full.names = TRUE
))

if (length(rds_files) > 0) {
    results_file <- tail(rds_files, 1)
    log_msg("Loading RDS: ", basename(results_file))
    results <- readr::read_rds(results_file)
} else if (length(csv_files) > 0) {
    results_file <- tail(csv_files, 1)
    log_msg("Loading CSV: ", basename(results_file))
    results <- readr::read_csv(results_file, show_col_types = FALSE)
} else {
    stop(
        "No power analysis results found in:\n  ", DATA_DIR, "\n\n",
        "Run a simulation first:\n",
        "  make power_analysis_dev        (seconds, small grid)\n",
        "  make power_analysis_gcp_prod   (hours, full grid)\n"
    )
}

required_cols <- c(
    "N_Level2", "Power", "Lower_CI", "Upper_CI", "ICC",
    "Random_Slope_Std", "Level1_Effect_Std", "Level2_Effect_Std",
    "XLevel_Intxn_Effect_Std", "Effect", "success"
)
missing_cols <- setdiff(required_cols, names(results))
if (length(missing_cols) > 0) {
    stop(
        "Results file is missing required columns: ",
        paste(missing_cols, collapse = ", "),
        "\n  File: ", results_file
    )
}

results <- results |> filter(success == TRUE)
log_msg("Loaded ", nrow(results), " successful result rows")
log_msg("N_Level2 values: ", paste(sort(unique(results$N_Level2)), collapse = ", "))
log_msg("Effect types: ", paste(unique(results$Effect), collapse = ", "))
log_msg("ICC levels: ", paste(sort(unique(results$ICC)), collapse = ", "))


# --- [2] Data preparation ---------------------------------------------------
log_msg("Phase 2: Preparing data for visualization")

# Nice effect labels
effect_labels <- c(
    "L1_Direct"                = "Level-1 Direct",
    "L2_Direct"                = "Level-2 Direct",
    "Cross_Level_Interaction"  = "Cross-Level Interaction"
)

# Determine reference (median) values for each parameter
ref_icc <- median(unique(results$ICC))
ref_rs <- median(unique(results$Random_Slope_Std))
ref_effect <- median(unique(results$Level1_Effect_Std))

log_msg(
    "Reference values — ICC: ", ref_icc,
    ", Random Slope: ", ref_rs,
    ", Effect Size: ", ref_effect
)

results <- results |>
    mutate(
        Effect_Label = factor(effect_labels[Effect],
            levels = c(
                "Level-1 Direct",
                "Level-2 Direct",
                "Cross-Level Interaction"
            )
        ),
        ICC_Label = factor(paste0("ICC = ", formatC(ICC, format = "f", digits = 2)),
            levels = paste0("ICC = ", formatC(
                sort(unique(ICC)),
                format = "f", digits = 2
            ))
        ),
        RS_Label = factor(
            paste0("RS = ", formatC(Random_Slope_Std,
                format = "f", digits = 2
            )),
            levels = paste0("RS = ", formatC(
                sort(unique(Random_Slope_Std)),
                format = "f", digits = 2
            ))
        ),
        Own_Effect_Std = case_when(
            Effect == "L1_Direct" ~ Level1_Effect_Std,
            Effect == "L2_Direct" ~ Level2_Effect_Std,
            Effect == "Cross_Level_Interaction" ~ XLevel_Intxn_Effect_Std
        ),
        Own_Effect_Label = factor(
            paste0("d = ", formatC(Own_Effect_Std, format = "f", digits = 2)),
            levels = paste0("d = ", formatC(
                sort(unique(c(
                    Level1_Effect_Std, Level2_Effect_Std,
                    XLevel_Intxn_Effect_Std
                ))),
                format = "f", digits = 2
            ))
        )
    )

# Guard: flag any Effect values not handled by case_when above
na_effects <- results |> filter(is.na(Own_Effect_Std)) |> pull(Effect) |> unique()
if (length(na_effects) > 0) {
    warning(
        "Own_Effect_Std is NA for unrecognized Effect values: ",
        paste(na_effects, collapse = ", "),
        " — these rows will be excluded from effect-size figures"
    )
}

# Dynamic palette sizing
n_effect_sizes <- length(unique(na.omit(results$Own_Effect_Label)))
n_rs_levels    <- length(unique(results$RS_Label))
n_effect_types <- length(unique(na.omit(results$Effect_Label)))

pal_effect_size <- if (n_effect_sizes <= 3) pal_3 else
    colorRampPalette(pal_3)(n_effect_sizes)
pal_rand_slope <- if (n_rs_levels <= 3) pal_3_dark else
    colorRampPalette(pal_3_dark)(n_rs_levels)
pal_effect_type <- if (n_effect_types <= 3) pal_3 else
    colorRampPalette(pal_3)(n_effect_types)

log_msg(
    "Palette sizes — effect_size: ", n_effect_sizes,
    ", rand_slope: ", n_rs_levels,
    ", effect_type: ", n_effect_types
)

# Error bar width scales with number of N points
n_sample_sizes <- length(unique(results$N_Level2))
eb_width <- max(5, diff(range(results$N_Level2)) / (n_sample_sizes * 3))


# --- [3] Figure 1: Primary power curves by effect size ----------------------
log_msg("Phase 3: Figure 1 — Primary power curves by effect size")

fig1_data <- results |>
    filter(
        Random_Slope_Std == ref_rs,
        (Effect == "L1_Direct" &
            Level2_Effect_Std == ref_effect &
            XLevel_Intxn_Effect_Std == ref_effect) |
            (Effect == "L2_Direct" &
                Level1_Effect_Std == ref_effect &
                XLevel_Intxn_Effect_Std == ref_effect) |
            (Effect == "Cross_Level_Interaction" &
                Level1_Effect_Std == ref_effect &
                Level2_Effect_Std == ref_effect)
    )

fig1 <- ggplot(
    fig1_data,
    aes(
        x = N_Level2, y = Power,
        color = Own_Effect_Label, fill = Own_Effect_Label
    )
) +
    geom_hline(
        yintercept = POWER_THRESHOLD, linetype = "dashed",
        color = "grey50", linewidth = 0.4
    ) +
    geom_ribbon(aes(ymin = Lower_CI, ymax = Upper_CI),
        alpha = 0.08, color = NA
    ) +
    geom_line(linewidth = 0.7) +
    geom_errorbar(aes(ymin = Lower_CI, ymax = Upper_CI),
        width = eb_width, linewidth = 0.35, alpha = 0.6
    ) +
    geom_point(size = 2, shape = 21, stroke = 0.5) +
    facet_grid(Effect_Label ~ ICC_Label) +
    scale_color_manual(values = pal_effect_size) +
    scale_fill_manual(values = pal_effect_size) +
    scale_y_continuous(
        limits = c(0, 1), breaks = seq(0, 1, 0.20),
        labels = scales::label_number(accuracy = 0.01)
    ) +
    scale_x_continuous(breaks = scales::pretty_breaks(n = 6)) +
    labs(
        title = "Statistical Power by Sample Size and Effect Size",
        subtitle = glue(
            "Random slope SD = {ref_rs}; ",
            "non-focal effects held at d = {ref_effect}"
        ),
        x = "Level-2 Sample Size (N)",
        y = "Power",
        color = "Standardized Effect",
        fill = "Standardized Effect"
    )

save_pdf(fig1, "01_power_curves_by_effect_size.pdf", width = 12, height = 10)


# --- [4] Figure 2: Random slope sensitivity ---------------------------------
log_msg("Phase 4: Figure 2 — Random slope sensitivity")

fig2_data <- results |>
    filter(
        Level1_Effect_Std == ref_effect,
        Level2_Effect_Std == ref_effect,
        XLevel_Intxn_Effect_Std == ref_effect
    )

fig2 <- ggplot(
    fig2_data,
    aes(
        x = N_Level2, y = Power,
        color = RS_Label, fill = RS_Label
    )
) +
    geom_hline(
        yintercept = POWER_THRESHOLD, linetype = "dashed",
        color = "grey50", linewidth = 0.4
    ) +
    geom_ribbon(aes(ymin = Lower_CI, ymax = Upper_CI),
        alpha = 0.08, color = NA
    ) +
    geom_line(linewidth = 0.7) +
    geom_errorbar(aes(ymin = Lower_CI, ymax = Upper_CI),
        width = eb_width, linewidth = 0.35, alpha = 0.6
    ) +
    geom_point(size = 2, shape = 21, stroke = 0.5) +
    facet_grid(Effect_Label ~ ICC_Label) +
    scale_color_manual(values = pal_rand_slope) +
    scale_fill_manual(values = pal_rand_slope) +
    scale_y_continuous(
        limits = c(0, 1), breaks = seq(0, 1, 0.20),
        labels = scales::label_number(accuracy = 0.01)
    ) +
    scale_x_continuous(breaks = scales::pretty_breaks(n = 6)) +
    labs(
        title = "Statistical Power by Sample Size and Random Slope Variance",
        subtitle = glue("All standardized effects = {ref_effect}"),
        x = "Level-2 Sample Size (N)",
        y = "Power",
        color = "Random Slope SD",
        fill = "Random Slope SD"
    )

save_pdf(fig2, "02_power_curves_by_random_slope.pdf", width = 12, height = 10)


# --- [5] Figure 3: Minimum N heatmap ----------------------------------------
log_msg("Phase 5: Figure 3 — Minimum N for 80% power heatmap")

fig3_data <- fig1_data |>
    group_by(Effect_Label, ICC, Own_Effect_Std) |>
    summarise(
        Min_N = if (any(Power >= POWER_THRESHOLD)) {
            min(N_Level2[Power >= POWER_THRESHOLD])
        } else {
            NA_real_
        },
        .groups = "drop"
    ) |>
    mutate(
        ICC_Label = factor(paste0("ICC = ", formatC(ICC, format = "f", digits = 2)),
            levels = paste0("ICC = ", formatC(
                sort(unique(ICC)),
                format = "f", digits = 2
            ))
        ),
        Effect_Size_Label = paste0("d = ", formatC(Own_Effect_Std,
            format = "f", digits = 2
        )),
        N_Display = if_else(is.na(Min_N), "> max N", as.character(as.integer(Min_N)))
    )

max_n <- max(results$N_Level2)

fig3 <- ggplot(
    fig3_data,
    aes(x = Effect_Size_Label, y = ICC_Label, fill = Min_N)
) +
    geom_tile(color = "white", linewidth = 1.2) +
    geom_text(aes(label = N_Display),
        size = 4.5, fontface = "bold", family = "serif"
    ) +
    facet_wrap(~Effect_Label, ncol = 3) +
    scale_fill_gradient(
        low = "#4DAF4A", high = "#E41A1C",
        na.value = "grey80",
        limits = c(0, max_n),
        labels = scales::label_comma(),
        name = "Min N for 80% Power"
    ) +
    labs(
        title = "Minimum Sample Size for 80% Power",
        subtitle = glue(
            "Random slope SD = {ref_rs}; ",
            "non-focal effects at d = {ref_effect}; ",
            "grey = not achieved within N = {max_n}"
        ),
        x = "Standardized Effect Size",
        y = NULL
    ) +
    theme(
        panel.grid = element_blank(),
        axis.ticks = element_blank()
    )

save_pdf(fig3, "03_minimum_n_heatmap.pdf", width = 12, height = 5)


# --- [6] Figure 4: Cross-level interaction full sensitivity ------------------
log_msg("Phase 6: Figure 4 — Cross-level interaction full sensitivity")

fig4_data <- results |>
    filter(
        Effect == "Cross_Level_Interaction",
        Level1_Effect_Std == ref_effect,
        Level2_Effect_Std == ref_effect
    ) |>
    mutate(
        XLevel_Label = factor(
            paste0("d = ", formatC(XLevel_Intxn_Effect_Std,
                format = "f", digits = 2
            )),
            levels = paste0("d = ", formatC(
                sort(unique(XLevel_Intxn_Effect_Std)),
                format = "f", digits = 2
            ))
        )
    )

fig4 <- ggplot(
    fig4_data,
    aes(
        x = N_Level2, y = Power,
        color = XLevel_Label, fill = XLevel_Label
    )
) +
    geom_hline(
        yintercept = POWER_THRESHOLD, linetype = "dashed",
        color = "grey50", linewidth = 0.4
    ) +
    geom_ribbon(aes(ymin = Lower_CI, ymax = Upper_CI),
        alpha = 0.08, color = NA
    ) +
    geom_line(linewidth = 0.7) +
    geom_errorbar(aes(ymin = Lower_CI, ymax = Upper_CI),
        width = eb_width, linewidth = 0.35, alpha = 0.6
    ) +
    geom_point(size = 2, shape = 21, stroke = 0.5) +
    facet_grid(ICC_Label ~ RS_Label) +
    scale_color_manual(values = pal_effect_size) +
    scale_fill_manual(values = pal_effect_size) +
    scale_y_continuous(
        limits = c(0, 1), breaks = seq(0, 1, 0.20),
        labels = scales::label_number(accuracy = 0.01)
    ) +
    scale_x_continuous(breaks = scales::pretty_breaks(n = 6)) +
    labs(
        title = "Cross-Level Interaction: Full Sensitivity Analysis",
        subtitle = glue("L1 and L2 direct effects held at d = {ref_effect}"),
        x = "Level-2 Sample Size (N)",
        y = "Power",
        color = "Interaction Effect",
        fill = "Interaction Effect"
    )

save_pdf(fig4, "04_cross_level_full_sensitivity.pdf", width = 12, height = 10)


# --- [7] Figure 5: Power plateau at medium parameters -----------------------
log_msg("Phase 7: Figure 5 — Power plateau at medium parameters")

fig5_data <- results |>
    filter(
        ICC == ref_icc,
        Level1_Effect_Std == ref_effect,
        Level2_Effect_Std == ref_effect,
        XLevel_Intxn_Effect_Std == ref_effect,
        Random_Slope_Std == ref_rs
    )

# Find N where power first exceeds threshold for each effect
threshold_n <- fig5_data |>
    group_by(Effect_Label) |>
    filter(Power >= POWER_THRESHOLD) |>
    slice_min(N_Level2, n = 1, with_ties = FALSE) |>
    ungroup() |>
    select(Effect_Label, N_Level2, Power)

fig5 <- ggplot(
    fig5_data,
    aes(
        x = N_Level2, y = Power,
        color = Effect_Label, fill = Effect_Label
    )
) +
    geom_hline(
        yintercept = POWER_THRESHOLD, linetype = "dashed",
        color = "grey50", linewidth = 0.4
    ) +
    geom_ribbon(aes(ymin = Lower_CI, ymax = Upper_CI),
        alpha = 0.08, color = NA
    ) +
    geom_line(linewidth = 0.8) +
    geom_errorbar(aes(ymin = Lower_CI, ymax = Upper_CI),
        width = eb_width, linewidth = 0.35, alpha = 0.5
    ) +
    geom_point(size = 2.5, shape = 21, stroke = 0.6)

# Annotate threshold crossings
if (nrow(threshold_n) > 0) {
    fig5 <- fig5 +
        geom_vline(
            data = threshold_n,
            aes(xintercept = N_Level2, color = Effect_Label),
            linetype = "dotted", linewidth = 0.5, show.legend = FALSE
        )
}

fig5 <- fig5 +
    scale_color_manual(values = pal_effect_type) +
    scale_fill_manual(values = pal_effect_type) +
    scale_y_continuous(
        limits = c(0, 1), breaks = seq(0, 1, 0.20),
        labels = scales::label_number(accuracy = 0.01)
    ) +
    scale_x_continuous(breaks = scales::pretty_breaks(n = 8)) +
    labs(
        title = "Power Across Sample Sizes at Medium Parameters",
        subtitle = glue(
            "ICC = {ref_icc}, all effects d = {ref_effect}, ",
            "random slope SD = {ref_rs}"
        ),
        x = "Level-2 Sample Size (N)",
        y = "Power",
        color = "Effect Type",
        fill = "Effect Type"
    )

save_pdf(fig5, "05_power_plateau_medium_params.pdf", width = 10, height = 6)


# --- [8] Figure 6: Unfaceted power curves (all effects) --------------------
log_msg("Phase 8: Figure 6 — Unfaceted power curves (all effects, single panel)")

fig6_data <- results |>
    filter(
        ICC == ref_icc,
        Level1_Effect_Std == ref_effect,
        Level2_Effect_Std == ref_effect,
        XLevel_Intxn_Effect_Std == ref_effect,
        Random_Slope_Std == ref_rs
    )

fig6 <- ggplot(
    fig6_data,
    aes(
        x = N_Level2, y = Power,
        color = Effect_Label, fill = Effect_Label
    )
) +
    geom_hline(
        yintercept = 0.80, linetype = "dashed",
        color = "grey50", linewidth = 0.4, alpha = 0.5
    ) +
    geom_hline(
        yintercept = 0.90, linetype = "dashed",
        color = "grey50", linewidth = 0.4, alpha = 0.5
    ) +
    annotate("text",
        x = min(fig6_data$N_Level2), y = 0.815,
        label = "80%", size = 3, color = "grey40",
        hjust = 0, family = "serif"
    ) +
    annotate("text",
        x = min(fig6_data$N_Level2), y = 0.915,
        label = "90%", size = 3, color = "grey40",
        hjust = 0, family = "serif"
    ) +
    geom_line(linewidth = 1) +
    geom_errorbar(aes(ymin = Lower_CI, ymax = Upper_CI),
        width = eb_width, linewidth = 0.4, alpha = 0.6
    ) +
    geom_point(size = 2.5, shape = 21, stroke = 0.6) +
    scale_color_manual(values = pal_effect_type) +
    scale_fill_manual(values = pal_effect_type) +
    scale_y_continuous(
        limits = c(0, 1), breaks = seq(0, 1, 0.10),
        labels = scales::label_number(accuracy = 0.01)
    ) +
    scale_x_continuous(
        limits = range(results$N_Level2),
        breaks = sort(unique(results$N_Level2)),
        labels = scales::label_comma()
    ) +
    labs(
        title = "Power Analysis: Sample Size Effects",
        subtitle = glue(
            "ICC = {ref_icc}, all effects d = {ref_effect}, ",
            "random slope SD = {ref_rs}"
        ),
        x = "Level-2 Sample Size (N)",
        y = "Statistical Power",
        color = "Effect Type",
        fill = "Effect Type"
    )

save_pdf(fig6, "06_power_curves_unfaceted.pdf", width = 10, height = 6)


# --- [9] Figure 7: Uniform effect size × ICC (faceted) ----------------------
log_msg("Phase 9: Figure 7 — Uniform effect size × ICC (3×3 faceted)")

# Select rows where all three effect sizes are equal ("uniform diagonal")
fig7_data <- results |>
    filter(
        Random_Slope_Std == ref_rs,
        Level1_Effect_Std == Level2_Effect_Std,
        Level2_Effect_Std == XLevel_Intxn_Effect_Std
    ) |>
    mutate(
        Uniform_Effect_Label = factor(
            paste0("d = ", formatC(Level1_Effect_Std, format = "f", digits = 2)),
            levels = paste0("d = ", formatC(
                sort(unique(Level1_Effect_Std)),
                format = "f", digits = 2
            ))
        )
    )

fig7 <- ggplot(
    fig7_data,
    aes(
        x = N_Level2, y = Power,
        color = Effect_Label, fill = Effect_Label
    )
) +
    geom_hline(
        yintercept = 0.80, linetype = "dashed",
        color = "grey50", linewidth = 0.4, alpha = 0.5
    ) +
    geom_hline(
        yintercept = 0.90, linetype = "dashed",
        color = "grey50", linewidth = 0.4, alpha = 0.5
    ) +
    geom_line(linewidth = 0.8) +
    geom_errorbar(aes(ymin = Lower_CI, ymax = Upper_CI),
        width = eb_width, linewidth = 0.35, alpha = 0.6
    ) +
    geom_point(size = 2, shape = 21, stroke = 0.5) +
    facet_grid(Uniform_Effect_Label ~ ICC_Label) +
    scale_color_manual(values = pal_effect_type) +
    scale_fill_manual(values = pal_effect_type) +
    scale_y_continuous(
        limits = c(0, 1), breaks = seq(0, 1, 0.10),
        labels = scales::label_number(accuracy = 0.01)
    ) +
    scale_x_continuous(
        limits = range(results$N_Level2),
        breaks = scales::pretty_breaks(n = 6)
    ) +
    labs(
        title = "Power by Sample Size: Uniform Effect Sizes Across ICC Levels",
        subtitle = glue("Random slope SD = {ref_rs}; all three effects set to same d per row"),
        x = "Level-2 Sample Size (N)",
        y = "Statistical Power",
        color = "Effect Type",
        fill = "Effect Type"
    )

save_pdf(fig7, "07_power_curves_by_icc_and_effect.pdf", width = 14, height = 10)


# --- [10] Figure 8: Own effect size × ICC (faceted) -------------------------
log_msg("Phase 10: Figure 8 — Own effect size × ICC (3×3 faceted)")

# Each effect varies its own size; non-focal effects held at median
fig8_data <- results |>
    filter(
        Random_Slope_Std == ref_rs,
        (Effect == "L1_Direct" &
            Level2_Effect_Std == ref_effect &
            XLevel_Intxn_Effect_Std == ref_effect) |
            (Effect == "L2_Direct" &
                Level1_Effect_Std == ref_effect &
                XLevel_Intxn_Effect_Std == ref_effect) |
            (Effect == "Cross_Level_Interaction" &
                Level1_Effect_Std == ref_effect &
                Level2_Effect_Std == ref_effect)
    )

fig8 <- ggplot(
    fig8_data,
    aes(
        x = N_Level2, y = Power,
        color = Effect_Label, fill = Effect_Label
    )
) +
    geom_hline(
        yintercept = 0.80, linetype = "dashed",
        color = "grey50", linewidth = 0.4, alpha = 0.5
    ) +
    geom_hline(
        yintercept = 0.90, linetype = "dashed",
        color = "grey50", linewidth = 0.4, alpha = 0.5
    ) +
    geom_line(linewidth = 0.8) +
    geom_errorbar(aes(ymin = Lower_CI, ymax = Upper_CI),
        width = eb_width, linewidth = 0.35, alpha = 0.6
    ) +
    geom_point(size = 2, shape = 21, stroke = 0.5) +
    facet_grid(Own_Effect_Label ~ ICC_Label) +
    scale_color_manual(values = pal_effect_type) +
    scale_fill_manual(values = pal_effect_type) +
    scale_y_continuous(
        limits = c(0, 1), breaks = seq(0, 1, 0.10),
        labels = scales::label_number(accuracy = 0.01)
    ) +
    scale_x_continuous(
        limits = range(results$N_Level2),
        breaks = scales::pretty_breaks(n = 6)
    ) +
    labs(
        title = "Power by Sample Size: Own Effect Size Across ICC Levels",
        subtitle = glue(
            "Random slope SD = {ref_rs}; ",
            "non-focal effects held at d = {ref_effect}"
        ),
        x = "Level-2 Sample Size (N)",
        y = "Statistical Power",
        color = "Effect Type",
        fill = "Effect Type"
    )

save_pdf(fig8, "08_power_curves_by_icc_own_effect.pdf", width = 14, height = 10)


# --- [11] Summary log -------------------------------------------------------
log_msg("Phase 11: Summary")

# Minimum N for 80% power at key parameter combinations
summary_tbl <- fig1_data |>
    group_by(Effect_Label, ICC, Own_Effect_Std) |>
    summarise(
        Min_N_80 = if (any(Power >= POWER_THRESHOLD)) {
            min(N_Level2[Power >= POWER_THRESHOLD])
        } else {
            NA_real_
        },
        .groups = "drop"
    ) |>
    arrange(Effect_Label, ICC, Own_Effect_Std)

log_msg(
    "Minimum N for 80% power (RS = ", ref_rs,
    ", non-focal effects = ", ref_effect, "):"
)
print(summary_tbl, n = Inf)

n_figs <- length(list.files(FIGS_DIR, pattern = "\\.pdf$"))
log_msg("Total PDF figures saved: ", n_figs)
log_msg("Output directory: ", FIGS_DIR)
log_msg("Visualization complete.")
