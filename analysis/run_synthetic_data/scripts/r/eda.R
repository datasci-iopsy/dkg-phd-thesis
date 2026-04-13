#!/usr/bin/env Rscript
# =============================================================================
# analysis/run_synthetic_data/scripts/r/eda.R
#
# Comprehensive Exploratory Data Analysis for the synthetic panel dataset.
# Comprehensive Exploratory Data Analysis for the synthetic panel dataset.
# Produces publication-quality SVG figures and diagnostic tables across 8
# phases: screening, demographics, distributions, multilevel structure,
# within-person dynamics, bivariate relationships, model diagnostics, and
# cross-level interaction exploration.
#
# Design: 800 participants × 3 within-day timepoints (2,391 rows × 81 cols)
# Output: SVG figures → analysis/run_synthetic_data/figs/eda/
# =============================================================================

# --- [0] Libraries and setup ------------------------------------------------
library(ggplot2)
library(patchwork)
library(cowplot)
library(corrplot)
library(ggridges)
library(ggdist)
library(ggrepel)
library(viridis)
library(scales)
library(gridExtra)
library(lme4)
library(lmerTest)
library(broom.mixed)
library(performance)
library(see)
library(effectsize)
library(parameters)
library(datawizard)
library(correlation)
library(rmcorr)
library(psych)
library(car)
library(dplyr)
library(tidyr)
library(purrr)
library(forcats)
library(stringr)
library(readr)
library(tibble)
library(here)
library(glue)

options(tibble.width = Inf)
here::here()

# Source shared utilities (log_msg, ensure_dir, load_config, theme_apa, save_svg)
source(here::here("analysis", "shared", "utils", "common_utils.r"))
source(here::here("analysis", "shared", "utils", "plot_utils.r"))

# --- Global settings ---------------------------------------------------------
FIGS_DIR <- here::here("analysis", "run_synthetic_data", "figs", "eda")
ensure_dir(FIGS_DIR)

theme_set(theme_apa)

# SVG save helper (binds FIGS_DIR for convenience at call sites)
save_fig <- function(plot, filename, width = 10, height = 7) {
    save_svg(plot, file.path(FIGS_DIR, filename), width, height)
}

# PDF save helper for table outputs (binds FIGS_DIR for convenience at call sites)
save_table <- function(plot, filename, width = 10, height = 7) {
    save_pdf(plot, file.path(FIGS_DIR, filename), width, height)
}

# Color palettes
pal_3 <- viridis::viridis(3, end = 0.85) # 3-level timepoint palette
pal_burnout <- viridis::viridis(3, option = "C", end = 0.85) # PF/CW/EE
pal_nf <- viridis::viridis(3, option = "D", end = 0.85) # COMP/AUTO/RELT


# =============================================================================
# [1] DATA LOADING AND PARTITIONING
# =============================================================================
log_msg("=== [1] Loading data ===")

export_files <- list.files(
    here::here("analysis", "run_synthetic_data", "data", "export"),
    pattern = "^syn_qualtrics_fct_panel_responses_.*\\.csv$",
    full.names = TRUE
)
if (length(export_files) == 0) stop("No export CSV found in data/export/")
export_path <- sort(export_files, decreasing = TRUE)[1]
log_msg("Loading: ", basename(export_path))
df_raw <- readr::read_csv(export_path, show_col_types = TRUE)
log_msg("Loaded: ", nrow(df_raw), " rows x ", ncol(df_raw), " columns")

tbls <- list()

# L2: one row per participant (time-invariant variables)
tbls$l2 <- df_raw |>
    dplyr::distinct(response_id, .keep_all = TRUE) |>
    dplyr::select(
        response_id, age, ethnicity, gender, job_tenure, edu_lvl, is_remote,
        pa_mean, na_mean, br_mean, vio_mean, js_mean
    )

# L1: all rows (time-varying variables)
tbls$l1 <- df_raw |>
    dplyr::select(
        response_id, timepoint, duration,
        pf_mean, cw_mean, ee_mean,
        comp_mean, auto_mean, relt_mean,
        atcb_mean, meetings_count, meetings_mins,
        turnover_intention_mean
    )

# Full merged (for cross-level analyses)
tbls$full <- df_raw |>
    dplyr::select(
        response_id, timepoint, duration,
        pf_mean, cw_mean, ee_mean,
        comp_mean, auto_mean, relt_mean,
        atcb_mean, meetings_count, meetings_mins,
        turnover_intention_mean,
        age, ethnicity, gender, job_tenure, edu_lvl, is_remote,
        pa_mean, na_mean, br_mean, vio_mean, js_mean
    )

# Reusable variable name vectors
l1_scale_vars <- c(
    "pf_mean", "cw_mean", "ee_mean",
    "comp_mean", "auto_mean", "relt_mean",
    "atcb_mean", "turnover_intention_mean"
)
l1_all_vars <- c(l1_scale_vars, "meetings_count", "meetings_mins")
l2_cont_vars <- c("pa_mean", "na_mean", "br_mean", "vio_mean", "js_mean")
l2_demo_cat <- c("ethnicity", "gender", "edu_lvl", "is_remote")

# Pretty labels for display
l1_labels <- c(
    pf_mean = "Physical Fatigue", cw_mean = "Cognitive Weariness",
    ee_mean = "Emotional Exhaustion", comp_mean = "NF: Competence",
    auto_mean = "NF: Autonomy", relt_mean = "NF: Relatedness",
    atcb_mean = "ATCB (Marker)", turnover_intention_mean = "Turnover Intention",
    meetings_count = "Meeting Count", meetings_mins = "Meeting Minutes"
)
l2_labels <- c(
    pa_mean = "Positive Affect", na_mean = "Negative Affect",
    br_mean = "PC Breach", vio_mean = "PC Violation",
    js_mean = "Job Satisfaction"
)

log_msg(
    "L2 participants: ", nrow(tbls$l2),
    " | L1 observations: ", nrow(tbls$l1)
)


# =============================================================================
# PHASE 1: DATA SCREENING AND QUALITY
# =============================================================================
log_msg("=== PHASE 1: Data Screening and Quality ===")

# --- 1.1 Missing data pattern -----------------------------------------------
log_msg("  1.1 Missing data pattern")

miss_rates <- df_raw |>
    dplyr::summarise(across(everything(), ~ mean(is.na(.)))) |>
    tidyr::pivot_longer(everything(),
        names_to = "variable",
        values_to = "pct_missing"
    ) |>
    dplyr::arrange(desc(pct_missing))

# If any missingness exists, plot it; otherwise note completeness
if (any(miss_rates$pct_missing > 0)) {
    p_miss <- miss_rates |>
        dplyr::filter(pct_missing > 0) |>
        ggplot(aes(x = reorder(variable, pct_missing), y = pct_missing)) +
        geom_col(fill = viridis::viridis(1)) +
        coord_flip() +
        scale_y_continuous(labels = scales::percent_format()) +
        labs(
            title = "Missing Data Rates by Variable",
            x = NULL, y = "Proportion Missing"
        )
} else {
    p_miss <- ggplot() +
        annotate("text",
            x = 0.5, y = 0.5, size = 6,
            label = "No missing data detected across all 81 variables"
        ) +
        theme_void() +
        labs(title = "Missing Data Screening: Complete Dataset")
}
save_fig(p_miss, "eda_01_missing_data_pattern.svg")


# --- 1.2 Survey duration diagnostics ----------------------------------------
log_msg("  1.2 Survey duration diagnostics")

p_duration <- tbls$l1 |>
    ggplot(aes(x = duration, fill = factor(timepoint))) +
    geom_density(alpha = 0.5) +
    geom_vline(xintercept = c(60, 1800), linetype = "dashed", color = "red") +
    scale_fill_viridis_d(name = "Timepoint", end = 0.85) +
    scale_x_log10(labels = scales::comma_format()) +
    labs(
        title = "Survey Completion Duration by Timepoint",
        subtitle = "Dashed lines at 60s (speeder) and 1800s (distracted)",
        x = "Duration (seconds, log scale)", y = "Density"
    )
save_fig(p_duration, "eda_02_duration_diagnostics.svg")


# --- 1.3 Univariate distributions: density + QQ -----------------------------
log_msg("  1.3 Univariate distributions")

make_dist_qq <- function(data, var, title) {
    p_dens <- ggplot(data, aes(x = .data[[var]])) +
        geom_density(fill = viridis::viridis(1, begin = 0.3), alpha = 0.6) +
        labs(title = title, x = var, y = "Density")
    p_qq <- ggplot(data, aes(sample = .data[[var]])) +
        stat_qq(alpha = 0.3, size = 0.8) +
        stat_qq_line(color = "red") +
        labs(x = "Theoretical Quantiles", y = "Sample Quantiles")
    p_dens + p_qq + plot_layout(ncol = 2)
}

# L1 distributions (pooled across timepoints)
l1_dist_plots <- purrr::map(
    l1_all_vars,
    ~ make_dist_qq(tbls$l1, .x, l1_labels[.x] %||% .x)
)
p_l1_dists <- patchwork::wrap_plots(l1_dist_plots, ncol = 1) +
    patchwork::plot_annotation(title = "L1 Variable Distributions (Pooled)")
save_fig(p_l1_dists, "eda_03a_l1_univariate_distributions.svg",
    width = 12, height = 30
)

# L2 distributions
l2_dist_plots <- purrr::map(
    l2_cont_vars,
    ~ make_dist_qq(tbls$l2, .x, l2_labels[.x] %||% .x)
)
p_l2_dists <- patchwork::wrap_plots(l2_dist_plots, ncol = 1) +
    patchwork::plot_annotation(title = "L2 Variable Distributions (Person-Level)")
save_fig(p_l2_dists, "eda_03b_l2_univariate_distributions.svg",
    width = 12, height = 18
)


# --- 1.4 Descriptive statistics table ----------------------------------------
log_msg("  1.4 Descriptive statistics table")

# L1 descriptives
l1_desc <- tbls$l1 |>
    dplyr::select(all_of(l1_all_vars)) |>
    psych::describe() |>
    as.data.frame() |>
    tibble::rownames_to_column("variable") |>
    dplyr::select(variable, n, mean, sd, min, max, skew, kurtosis, se) |>
    dplyr::mutate(level = "L1")

# L2 descriptives
l2_desc <- tbls$l2 |>
    dplyr::select(all_of(l2_cont_vars), age) |>
    psych::describe() |>
    as.data.frame() |>
    tibble::rownames_to_column("variable") |>
    dplyr::select(variable, n, mean, sd, min, max, skew, kurtosis, se) |>
    dplyr::mutate(level = "L2")

all_desc <- dplyr::bind_rows(l1_desc, l2_desc) |>
    dplyr::mutate(across(c(mean, sd, min, max, skew, kurtosis, se),
        ~ round(., 3)
    ))

# Floor/ceiling for Likert scales (1-5 range)
floor_ceil <- tbls$l1 |>
    dplyr::summarise(across(all_of(l1_scale_vars),
        list(
            floor = ~ mean(. <= 1, na.rm = TRUE),
            ceil = ~ mean(. >= 5, na.rm = TRUE)
        )
    )) |>
    tidyr::pivot_longer(everything(),
        names_to = c("variable", ".value"),
        names_pattern = "(.+)_(floor|ceil)"
    ) |>
    dplyr::mutate(across(c(floor, ceil), ~ round(., 4)))

# Print to console
cat("\n=== Descriptive Statistics ===\n")
print(as.data.frame(all_desc))
cat("\n=== Floor/Ceiling (L1 Scales) ===\n")
print(as.data.frame(floor_ceil))

# Save as SVG table
desc_grob <- gridExtra::tableGrob(all_desc,
    rows = NULL,
    theme = gridExtra::ttheme_minimal(base_size = 8)
)
p_desc <- cowplot::ggdraw() +
    cowplot::draw_grob(desc_grob) +
    labs(title = "Descriptive Statistics: All Scales")
save_table(p_desc, "eda_04_descriptive_statistics.pdf", width = 12, height = 8)


# --- 1.5 Mahalanobis distance (L2) ------------------------------------------
log_msg("  1.5 Mahalanobis distance")

l2_numeric <- tbls$l2 |> dplyr::select(all_of(l2_cont_vars))
md <- mahalanobis(
    l2_numeric,
    colMeans(l2_numeric, na.rm = TRUE),
    cov(l2_numeric, use = "complete.obs")
)
tbls$l2$mahal_dist <- md
crit_val <- qchisq(0.999, df = length(l2_cont_vars))
n_outliers <- sum(md > crit_val)

p_mahal <- ggplot(tibble::tibble(md = sort(md)), aes(sample = md)) +
    stat_qq(
        distribution = qchisq,
        dparams = list(df = length(l2_cont_vars)),
        alpha = 0.3
    ) +
    stat_qq_line(
        distribution = qchisq,
        dparams = list(df = length(l2_cont_vars)),
        color = "red"
    ) +
    geom_hline(yintercept = crit_val, linetype = "dashed", color = "red") +
    labs(
        title = "Mahalanobis Distance: L2 Continuous Variables",
        subtitle = glue(
            "Critical value at p < .001: {round(crit_val, 2)} | ",
            "Flagged: {n_outliers} participants"
        ),
        x = "Chi-squared Quantiles", y = "Mahalanobis Distance"
    )
save_fig(p_mahal, "eda_05_mahalanobis_l2.svg")


# --- 1.6 Marker variable (ATCB) diagnostics ---------------------------------
log_msg("  1.6 Marker variable diagnostics")

# ATCB correlations with all other L1 scales
atcb_cors <- tbls$l1 |>
    dplyr::select(-response_id, -timepoint, -duration) |>
    correlation::correlation(method = "pearson") |>
    dplyr::filter(Parameter1 == "atcb_mean" | Parameter2 == "atcb_mean") |>
    dplyr::mutate(
        other_var = ifelse(Parameter1 == "atcb_mean", Parameter2, Parameter1)
    ) |>
    dplyr::filter(other_var != "atcb_mean")

p_atcb <- atcb_cors |>
    ggplot(aes(x = reorder(other_var, abs(r)), y = r)) +
    geom_col(fill = viridis::viridis(1, begin = 0.5)) +
    geom_hline(
        yintercept = c(-0.10, 0.10),
        linetype = "dashed", color = "red"
    ) +
    coord_flip() +
    labs(
        title = "Marker Variable (ATCB) Correlations with Substantive Variables",
        subtitle = "Dashed lines at r = +/- .10 (Lindell & Whitney threshold)",
        x = NULL, y = "Pearson r"
    )
save_fig(p_atcb, "eda_06_marker_variable_diagnostics.svg")


# =============================================================================
# PHASE 2: SAMPLE CHARACTERISTICS
# =============================================================================
log_msg("=== PHASE 2: Sample Characteristics ===")

# --- 2.1 Demographic bar charts (categorical) -------------------------------
log_msg("  2.1 Demographic bar charts")

make_demo_bar <- function(data, var, title) {
    data |>
        dplyr::mutate(across(all_of(var), as.character)) |>
        dplyr::count(.data[[var]]) |>
        dplyr::mutate(pct = n / sum(n)) |>
        ggplot(aes(x = forcats::fct_reorder(.data[[var]], n), y = n)) +
        geom_col(fill = viridis::viridis(1, begin = 0.4)) +
        geom_text(
            aes(label = glue("{n} ({scales::percent(pct, accuracy = 0.1)})")),
            hjust = -0.1, size = 3
        ) +
        coord_flip() +
        labs(title = title, x = NULL, y = "Count")
}

demo_plots <- purrr::map2(
    l2_demo_cat,
    c("Ethnicity", "Gender", "Education Level", "Remote Work Status"),
    ~ make_demo_bar(tbls$l2, .x, .y)
)
p_demos <- patchwork::wrap_plots(demo_plots, ncol = 2) +
    patchwork::plot_annotation(title = "Sample Demographics (N = 800)")
save_fig(p_demos, "eda_07_demographic_distributions.svg", width = 14, height = 10)


# --- 2.2 Age distribution ---------------------------------------------------
log_msg("  2.2 Age distribution")

age_stats <- tbls$l2 |>
    dplyr::summarise(
        M = mean(age, na.rm = TRUE), SD = sd(age, na.rm = TRUE),
        Min = min(age, na.rm = TRUE), Max = max(age, na.rm = TRUE)
    )

p_age <- ggplot(tbls$l2, aes(x = age)) +
    geom_histogram(
        aes(y = after_stat(density)),
        bins = 25,
        fill = viridis::viridis(1, begin = 0.3), alpha = 0.7
    ) +
    geom_density(linewidth = 0.8) +
    annotate("text",
        x = Inf, y = Inf, hjust = 1.1, vjust = 1.5, size = 3.5,
        label = glue(
            "M = {round(age_stats$M, 1)}, SD = {round(age_stats$SD, 1)}\n",
            "Range: {age_stats$Min}-{age_stats$Max}"
        )
    ) +
    labs(title = "Age Distribution", x = "Age (years)", y = "Density")
save_fig(p_age, "eda_08_age_distribution.svg")


# --- 2.3 Cross-tabulations --------------------------------------------------
log_msg("  2.3 Cross-tabulations")

p_cross_1 <- tbls$l2 |>
    dplyr::count(gender, is_remote) |>
    ggplot(aes(x = gender, y = n, fill = factor(is_remote))) +
    geom_col(position = "dodge") +
    scale_fill_viridis_d(
        name = "Remote",
        labels = c("No", "Yes"), end = 0.85
    ) +
    labs(title = "Gender × Remote Work Status", x = NULL, y = "Count")

p_cross_2 <- tbls$l2 |>
    dplyr::count(ethnicity, edu_lvl) |>
    ggplot(aes(x = ethnicity, y = n, fill = edu_lvl)) +
    geom_col(position = "dodge") +
    scale_fill_viridis_d(name = "Education", end = 0.85) +
    labs(title = "Ethnicity × Education Level", x = NULL, y = "Count") +
    theme(axis.text.x = element_text(angle = 30, hjust = 1))

p_crosstabs <- p_cross_1 / p_cross_2 +
    patchwork::plot_annotation(title = "Demographic Cross-Tabulations")
save_fig(p_crosstabs, "eda_09_demographic_crosstabs.svg", height = 10)


# --- 2.4 APA-Style Table 1 --------------------------------------------------
log_msg("  2.4 APA-style Table 1")

# Categorical summaries
cat_summary <- purrr::map_dfr(l2_demo_cat, function(v) {
    tbls$l2 |>
        dplyr::count(.data[[v]]) |>
        dplyr::mutate(
            pct = scales::percent(n / sum(n), accuracy = 0.1),
            variable = v,
            level = as.character(.data[[v]])
        ) |>
        dplyr::select(variable, level, n, pct)
})

# Continuous summaries
cont_summary <- tbls$l2 |>
    dplyr::select(age, all_of(l2_cont_vars)) |>
    psych::describe() |>
    as.data.frame() |>
    tibble::rownames_to_column("variable") |>
    dplyr::select(variable, n, mean, sd) |>
    dplyr::mutate(across(c(mean, sd), ~ round(., 2)))

# Render to SVG
t1_cat_grob <- gridExtra::tableGrob(cat_summary,
    rows = NULL,
    theme = gridExtra::ttheme_minimal(base_size = 8)
)
t1_cont_grob <- gridExtra::tableGrob(cont_summary,
    rows = NULL,
    theme = gridExtra::ttheme_minimal(base_size = 8)
)

pdf(file.path(FIGS_DIR, "eda_10_table1.pdf"), width = 10, height = 14)
gridExtra::grid.arrange(
    t1_cont_grob, t1_cat_grob,
    nrow = 2,
    top = grid::textGrob("Table 1: Sample Characteristics",
        gp = grid::gpar(fontsize = 14, fontface = "bold")
    )
)
dev.off()
log_msg("Saved: ", file.path(FIGS_DIR, "eda_10_table1.pdf"))


# =============================================================================
# PHASE 3: SCALE-LEVEL DISTRIBUTIONS
# =============================================================================
log_msg("=== PHASE 3: Scale-Level Distributions ===")

# --- 3.1 Raincloud plots for L1 (by timepoint) ------------------------------
log_msg("  3.1 Raincloud plots")

p_raincloud <- tbls$l1 |>
    tidyr::pivot_longer(
        cols = all_of(l1_scale_vars),
        names_to = "scale", values_to = "value"
    ) |>
    dplyr::mutate(scale = factor(scale, levels = l1_scale_vars)) |>
    ggplot(aes(x = factor(timepoint), y = value, fill = factor(timepoint))) +
    ggdist::stat_halfeye(
        adjust = 0.8, width = 0.6, .width = 0,
        justification = -0.2, point_colour = NA
    ) +
    geom_boxplot(width = 0.15, outlier.shape = NA, alpha = 0.5) +
    scale_fill_viridis_d(end = 0.85, guide = "none") +
    facet_wrap(~scale, scales = "free_y", ncol = 4,
        labeller = labeller(scale = l1_labels)
    ) +
    labs(
        title = "L1 Scale Distributions by Timepoint (Raincloud Plots)",
        x = "Timepoint", y = "Scale Mean"
    )
save_fig(p_raincloud, "eda_11_l1_raincloud_by_timepoint.svg",
    width = 14, height = 10
)


# --- 3.2 Ridgeline plots for burnout and NF ---------------------------------
log_msg("  3.2 Ridgeline plots")

p_ridge_burn <- tbls$l1 |>
    tidyr::pivot_longer(
        cols = c(pf_mean, cw_mean, ee_mean),
        names_to = "subscale", values_to = "value"
    ) |>
    dplyr::mutate(subscale = factor(subscale,
        levels = c("pf_mean", "cw_mean", "ee_mean"),
        labels = c("Physical Fatigue", "Cognitive Weariness", "Emotional Exhaustion")
    )) |>
    ggplot(aes(x = value, y = subscale, fill = subscale)) +
    ggridges::geom_density_ridges(alpha = 0.7, scale = 1.2) +
    scale_fill_manual(values = pal_burnout, guide = "none") +
    labs(
        title = "Burnout Subscale Distributions (SMBM)",
        x = "Scale Mean", y = NULL
    )
save_fig(p_ridge_burn, "eda_12a_burnout_ridgelines.svg", width = 8, height = 5)

p_ridge_nf <- tbls$l1 |>
    tidyr::pivot_longer(
        cols = c(comp_mean, auto_mean, relt_mean),
        names_to = "subscale", values_to = "value"
    ) |>
    dplyr::mutate(subscale = factor(subscale,
        levels = c("comp_mean", "auto_mean", "relt_mean"),
        labels = c("Competence", "Autonomy", "Relatedness")
    )) |>
    ggplot(aes(x = value, y = subscale, fill = subscale)) +
    ggridges::geom_density_ridges(alpha = 0.7, scale = 1.2) +
    scale_fill_manual(values = pal_nf, guide = "none") +
    labs(
        title = "Need Frustration Subscale Distributions (PNTS)",
        x = "Scale Mean", y = NULL
    )
save_fig(p_ridge_nf, "eda_12b_need_frustration_ridgelines.svg",
    width = 8, height = 5
)


# --- 3.3 L2 variable distributions ------------------------------------------
log_msg("  3.3 L2 distributions")

p_l2_dist <- tbls$l2 |>
    tidyr::pivot_longer(
        cols = all_of(l2_cont_vars),
        names_to = "scale", values_to = "value"
    ) |>
    dplyr::mutate(scale = factor(scale,
        levels = l2_cont_vars,
        labels = l2_labels[l2_cont_vars]
    )) |>
    ggplot(aes(x = scale, y = value, fill = scale)) +
    geom_violin(alpha = 0.5, draw_quantiles = c(0.25, 0.5, 0.75)) +
    geom_boxplot(width = 0.1, outlier.shape = 21, alpha = 0.7) +
    scale_fill_viridis_d(end = 0.85, guide = "none") +
    labs(
        title = "L2 Scale Distributions (Person-Level)",
        x = NULL, y = "Scale Mean"
    )
save_fig(p_l2_dist, "eda_13_l2_distributions.svg")


# --- 3.4 Skewness/Kurtosis diagnostic panel ---------------------------------
log_msg("  3.4 Skewness/kurtosis panel")

sk_l1 <- tbls$l1 |>
    dplyr::select(all_of(l1_all_vars)) |>
    psych::describe() |>
    as.data.frame() |>
    tibble::rownames_to_column("var") |>
    dplyr::mutate(level = "L1")

sk_l2 <- tbls$l2 |>
    dplyr::select(all_of(l2_cont_vars)) |>
    psych::describe() |>
    as.data.frame() |>
    tibble::rownames_to_column("var") |>
    dplyr::mutate(level = "L2")

all_sk <- dplyr::bind_rows(sk_l1, sk_l2)

p_sk <- ggplot(all_sk, aes(
    x = skew, y = reorder(var, skew),
    size = abs(kurtosis), color = level
)) +
    geom_point(alpha = 0.8) +
    geom_vline(xintercept = c(-2, 2), linetype = "dashed", color = "red") +
    scale_size_continuous(name = "|Kurtosis|", range = c(2, 8)) +
    scale_color_viridis_d(name = "Level", end = 0.7) +
    labs(
        title = "Skewness and Kurtosis Across All Scales",
        subtitle = "Dashed lines at skewness = ±2 (Curran et al., 1996)",
        x = "Skewness", y = NULL
    )
save_fig(p_sk, "eda_14_skew_kurtosis_panel.svg")


# =============================================================================
# PHASE 4: MULTILEVEL STRUCTURE EXPLORATION
# =============================================================================
log_msg("=== PHASE 4: Multilevel Structure Exploration ===")

# --- 4.1 ICC computation for all L1 variables --------------------------------
log_msg("  4.1 ICC computation")

# Fit unconditional means models and extract ICCs
ucm_fits <- purrr::map(l1_scale_vars, function(var) {
    formula <- as.formula(paste(var, "~ 1 + (1 | response_id)"))
    lme4::lmer(formula, data = tbls$l1, REML = TRUE)
})
names(ucm_fits) <- l1_scale_vars

icc_results <- purrr::map_dfr(l1_scale_vars, function(var) {
    fit <- ucm_fits[[var]]
    icc_val <- performance::icc(fit)
    vc <- as.data.frame(VarCorr(fit))

    var_between <- vc$vcov[vc$grp == "response_id"]
    var_within <- vc$vcov[vc$grp == "Residual"]

    tibble::tibble(
        variable     = var,
        icc_adjusted = icc_val$ICC_adjusted,
        var_between  = var_between,
        var_within   = var_within,
        var_total    = var_between + var_within,
        pct_between  = var_between / (var_between + var_within),
        pct_within   = var_within / (var_between + var_within)
    )
})

cat("\n=== ICC Results ===\n")
print(as.data.frame(icc_results))

# Save ICC table as CSV
readr::write_csv(icc_results, file.path(FIGS_DIR, "eda_15_icc_table.csv"))
log_msg("Saved: ", file.path(FIGS_DIR, "eda_15_icc_table.csv"))

# Render ICC table as SVG
icc_display <- icc_results |>
    dplyr::mutate(across(where(is.numeric), ~ round(., 3)))
icc_grob <- gridExtra::tableGrob(icc_display,
    rows = NULL,
    theme = gridExtra::ttheme_minimal(base_size = 9)
)
pdf(file.path(FIGS_DIR, "eda_15_icc_table.pdf"), width = 12, height = 5)
grid::grid.draw(icc_grob)
dev.off()
log_msg("Saved: ", file.path(FIGS_DIR, "eda_15_icc_table.pdf"))


# --- 4.2 ICC bar chart with power analysis reference lines -------------------
log_msg("  4.2 ICC bar chart")

p_icc <- ggplot(
    icc_results,
    aes(x = reorder(variable, icc_adjusted), y = icc_adjusted)
) +
    geom_col(fill = viridis::viridis(1, begin = 0.4)) +
    geom_hline(
        yintercept = c(0.10, 0.30, 0.50),
        linetype = "dashed",
        color = c("forestgreen", "orange", "red"),
        linewidth = 0.5
    ) +
    annotate("text",
        x = 0.6, y = c(0.12, 0.32, 0.52),
        label = c("ICC = .10", "ICC = .30", "ICC = .50"),
        hjust = 0, size = 2.8,
        color = c("forestgreen", "orange3", "red3")
    ) +
    coord_flip() +
    scale_y_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.1)) +
    labs(
        title = "Intraclass Correlation Coefficients (L1 Variables)",
        subtitle = "Dashed lines correspond to power analysis ICC scenarios",
        x = NULL, y = "ICC (Adjusted)"
    )
save_fig(p_icc, "eda_16_icc_barchart.svg")


# --- 4.3 Variance decomposition (stacked bar) -------------------------------
log_msg("  4.3 Variance decomposition")

p_vardecomp <- icc_results |>
    dplyr::mutate(var_order = pct_within) |>
    tidyr::pivot_longer(
        cols = c(pct_within, pct_between),
        names_to = "component", values_to = "proportion"
    ) |>
    dplyr::mutate(component = ifelse(component == "pct_within",
        "Within-Person", "Between-Person"
    )) |>
    ggplot(aes(
        x = reorder(variable, var_order),
        y = proportion, fill = component
    )) +
    geom_col() +
    scale_fill_viridis_d(name = "Variance Component", end = 0.7) +
    coord_flip() +
    scale_y_continuous(labels = scales::percent_format()) +
    labs(
        title = "Variance Decomposition: Within vs. Between Person",
        x = NULL, y = "Proportion of Total Variance"
    )
save_fig(p_vardecomp, "eda_17_variance_decomposition.svg")


# --- 4.4 Spaghetti plots (individual trajectories) --------------------------
log_msg("  4.4 Spaghetti plots")

set.seed(42)
sampled_ids <- tbls$l1$response_id


make_spaghetti <- function(data, var, title, sample_ids) {
    group_means <- data |>
        dplyr::group_by(timepoint) |>
        dplyr::summarise(
            m = mean(.data[[var]], na.rm = TRUE),
            se = sd(.data[[var]], na.rm = TRUE) / sqrt(dplyr::n()),
            .groups = "drop"
        )

    ggplot() +
        geom_line(
            data = data |> dplyr::filter(response_id %in% sample_ids),
            aes(x = timepoint, y = .data[[var]], group = response_id),
            alpha = 0.08, color = "grey50"
        ) +
        geom_ribbon(
            data = group_means,
            aes(x = timepoint, ymin = m - 1.96 * se, ymax = m + 1.96 * se),
            fill = viridis::viridis(1, begin = 0.4), alpha = 0.3
        ) +
        geom_line(
            data = group_means, aes(x = timepoint, y = m),
            color = viridis::viridis(1, begin = 0.4), linewidth = 1.2
        ) +
        geom_point(
            data = group_means, aes(x = timepoint, y = m),
            color = viridis::viridis(1, begin = 0.4), size = 3
        ) +
        scale_x_continuous(breaks = 1:3) +
        labs(title = title, x = "Timepoint", y = var)
}

spaghetti_plots <- purrr::map2(
    l1_scale_vars,
    l1_labels[l1_scale_vars],
    ~ make_spaghetti(tbls$l1, .x, .y, sampled_ids)
)
p_spaghetti <- patchwork::wrap_plots(spaghetti_plots, ncol = 4) +
    patchwork::plot_annotation(
        title = "Individual Trajectories (All Participants) + Group Mean"
    )
save_fig(p_spaghetti, "eda_18_spaghetti_plots.svg", width = 16, height = 10)


# --- 4.5 Person-level SD distributions --------------------------------------
log_msg("  4.5 Person-level SD distributions")

person_sds <- tbls$l1 |>
    dplyr::group_by(response_id) |>
    dplyr::summarise(
        across(all_of(l1_scale_vars),
            ~ sd(., na.rm = TRUE),
            .names = "{.col}_sd"
        ),
        .groups = "drop"
    )

p_person_sd <- person_sds |>
    tidyr::pivot_longer(-response_id,
        names_to = "variable", values_to = "person_sd"
    ) |>
    dplyr::mutate(variable = stringr::str_remove(variable, "_sd$")) |>
    ggplot(aes(x = person_sd)) +
    geom_histogram(
        aes(y = after_stat(density)),
        bins = 30,
        fill = viridis::viridis(1, begin = 0.3), alpha = 0.7
    ) +
    geom_density(linewidth = 0.7) +
    facet_wrap(~variable, scales = "free", ncol = 4) +
    labs(
        title = "Distribution of Person-Level Standard Deviations",
        subtitle = "Higher values = more within-person fluctuation",
        x = "Person SD (across 3 timepoints)", y = "Density"
    )
save_fig(p_person_sd, "eda_19_person_sd_distributions.svg", width = 14, height = 8)


# --- 4.6 Random intercept distributions -------------------------------------
log_msg("  4.6 Random intercept distributions")

ri_dfs <- purrr::map_dfr(l1_scale_vars, function(var) {
    fit <- ucm_fits[[var]]
    ri <- ranef(fit)$response_id
    tibble::tibble(variable = var, random_intercept = ri[, 1])
})

p_ri <- ggplot(ri_dfs, aes(x = random_intercept, fill = variable)) +
    geom_density(alpha = 0.5) +
    facet_wrap(~variable, scales = "free", ncol = 4) +
    scale_fill_viridis_d(guide = "none", end = 0.85) +
    labs(
        title = "Random Intercept Distributions (Unconditional Models)",
        x = "Random Intercept (BLUP)", y = "Density"
    )
save_fig(p_ri, "eda_20_random_intercept_distributions.svg",
    width = 14, height = 8
)


# =============================================================================
# PHASE 5: WITHIN-PERSON DYNAMICS
# =============================================================================
log_msg("=== PHASE 5: Within-Person Dynamics ===")

# --- 5.1 Person-mean centering (CWC) diagnostics ----------------------------
log_msg("  5.1 CWC diagnostics")

tbls$l1_cwc <- tbls$l1 |>
    dplyr::group_by(response_id) |>
    dplyr::mutate(across(all_of(l1_scale_vars),
        list(cwc = ~ . - mean(., na.rm = TRUE)),
        .names = "{.col}_{.fn}"
    )) |>
    dplyr::ungroup()

cwc_vars <- paste0(l1_scale_vars, "_cwc")

p_cwc <- tbls$l1_cwc |>
    tidyr::pivot_longer(
        cols = all_of(cwc_vars),
        names_to = "variable", values_to = "cwc_value"
    ) |>
    dplyr::mutate(variable = stringr::str_remove(variable, "_cwc$")) |>
    ggplot(aes(x = cwc_value, fill = variable)) +
    geom_density(alpha = 0.5) +
    geom_vline(xintercept = 0, linetype = "dashed") +
    facet_wrap(~variable, scales = "free", ncol = 4) +
    scale_fill_viridis_d(guide = "none", end = 0.85) +
    labs(
        title = "Within-Person Centered (CWC) Score Distributions",
        subtitle = "Deviations from each person's mean across 3 timepoints",
        x = "CWC Score", y = "Density"
    )
save_fig(p_cwc, "eda_21_cwc_distributions.svg", width = 14, height = 8)


# --- 5.2 Timepoint-level means with SE bands --------------------------------
log_msg("  5.2 Timepoint means")

timepoint_means <- tbls$l1 |>
    tidyr::pivot_longer(
        cols = all_of(l1_scale_vars),
        names_to = "variable", values_to = "value"
    ) |>
    dplyr::group_by(variable, timepoint) |>
    dplyr::summarise(
        m = mean(value, na.rm = TRUE),
        se = sd(value, na.rm = TRUE) / sqrt(dplyr::n()),
        .groups = "drop"
    )

p_tp_means <- ggplot(
    timepoint_means,
    aes(x = factor(timepoint), y = m, group = variable)
) +
    geom_pointrange(
        aes(ymin = m - 1.96 * se, ymax = m + 1.96 * se),
        color = viridis::viridis(1, begin = 0.4), size = 0.4
    ) +
    geom_line(color = viridis::viridis(1, begin = 0.4)) +
    facet_wrap(~variable, scales = "free_y", ncol = 4) +
    labs(
        title = "Scale Means by Timepoint (with 95% CI)",
        x = "Timepoint", y = "Mean"
    )
save_fig(p_tp_means, "eda_22_timepoint_means.svg", width = 14, height = 8)


# --- 5.3 Trajectory clustering (exploratory) --------------------------------
log_msg("  5.3 Trajectory clustering")

traj_features <- tbls$l1 |>
    dplyr::group_by(response_id) |>
    dplyr::summarise(
        ti_mean = mean(turnover_intention_mean, na.rm = TRUE),
        ti_sd = sd(turnover_intention_mean, na.rm = TRUE),
        ti_slope = coef(lm(turnover_intention_mean ~ timepoint))[2],
        .groups = "drop"
    ) |>
    dplyr::mutate(ti_sd = tidyr::replace_na(ti_sd, 0))

set.seed(42)
km <- kmeans(
    scale(traj_features |> dplyr::select(-response_id)),
    centers = 3, nstart = 25
)
traj_features$cluster <- factor(km$cluster)

p_cluster <- tbls$l1 |>
    dplyr::left_join(
        traj_features |> dplyr::select(response_id, cluster),
        by = "response_id"
    ) |>
    ggplot(aes(
        x = timepoint, y = turnover_intention_mean,
        group = response_id, color = cluster
    )) +
    geom_line(alpha = 0.1) +
    stat_summary(aes(group = cluster),
        fun = mean,
        geom = "line", linewidth = 1.5
    ) +
    stat_summary(aes(group = cluster),
        fun = mean,
        geom = "point", size = 3
    ) +
    scale_color_viridis_d(name = "Cluster", end = 0.85) +
    scale_x_continuous(breaks = 1:3) +
    labs(
        title = "Turnover Intention Trajectories by Cluster (Exploratory)",
        subtitle = "K-means (k=3) on person-level mean, SD, and slope",
        x = "Timepoint", y = "Turnover Intention"
    )
save_fig(p_cluster, "eda_23_trajectory_clusters.svg")


# --- 5.4 Lag-1 autocorrelations within persons ------------------------------
log_msg("  5.4 Lag-1 autocorrelations")

lag1_cors <- tbls$l1 |>
    dplyr::arrange(response_id, timepoint) |>
    dplyr::group_by(response_id) |>
    dplyr::summarise(
        across(all_of(l1_scale_vars),
            ~ cor(.[1:2], .[2:3], use = "complete.obs"),
            .names = "{.col}_lag1r"
        ),
        .groups = "drop"
    )

p_lag1 <- lag1_cors |>
    tidyr::pivot_longer(-response_id,
        names_to = "variable", values_to = "lag1_r"
    ) |>
    dplyr::mutate(variable = stringr::str_remove(variable, "_lag1r$")) |>
    dplyr::filter(!is.na(lag1_r)) |>
    ggplot(aes(x = lag1_r)) +
    geom_histogram(
        bins = 30,
        fill = viridis::viridis(1, begin = 0.3), alpha = 0.7
    ) +
    geom_vline(xintercept = 0, linetype = "dashed") +
    facet_wrap(~variable, ncol = 4) +
    labs(
        title = "Distribution of Lag-1 Autocorrelations (Within-Person)",
        subtitle = "Each bar = number of persons with that autocorrelation",
        x = "Lag-1 Autocorrelation", y = "Count"
    )
save_fig(p_lag1, "eda_24_lag1_autocorrelations.svg", width = 14, height = 8)


# =============================================================================
# PHASE 6: BIVARIATE RELATIONSHIPS
# =============================================================================
log_msg("=== PHASE 6: Bivariate Relationships ===")

# --- 6.1 L2 correlation matrix ----------------------------------------------
log_msg("  6.1 L2 correlation matrix")

l2_cor_data <- tbls$l2 |>
    dplyr::select(age, all_of(l2_cont_vars))
l2_cor_mat <- cor(l2_cor_data, use = "complete.obs")

svg(file.path(FIGS_DIR, "eda_25_l2_correlation_matrix.svg"),
    width = 9, height = 9
)
corrplot::corrplot(l2_cor_mat,
    method = "color", type = "lower",
    addCoef.col = "black", number.cex = 0.7,
    tl.col = "black", tl.cex = 0.9,
    title = "L2 Between-Person Correlation Matrix",
    mar = c(0, 0, 2, 0)
)
dev.off()
log_msg("Saved: ", file.path(FIGS_DIR, "eda_25_l2_correlation_matrix.svg"))


# --- 6.2 Within-person (CWC) scatterplots -----------------------------------
log_msg("  6.2 CWC scatterplots")

key_predictors <- c("pf_mean", "cw_mean", "ee_mean", "comp_mean", "auto_mean", "relt_mean")
cwc_preds <- paste0(key_predictors, "_cwc")
cwc_dv <- "turnover_intention_mean_cwc"

cwc_scatter_plots <- purrr::map(cwc_preds, function(pred) {
    pred_label <- stringr::str_remove(pred, "_cwc$")
    ggplot(tbls$l1_cwc, aes(x = .data[[pred]], y = .data[[cwc_dv]])) +
        geom_point(alpha = 0.08, size = 0.5) +
        geom_smooth(
            method = "lm",
            color = viridis::viridis(1, begin = 0.4),
            se = TRUE, linewidth = 1
        ) +
        labs(
            x = paste0(pred_label, " (CWC)"),
            y = "Turnover Intention (CWC)"
        )
})

p_cwc_scatter <- patchwork::wrap_plots(cwc_scatter_plots, ncol = 3) +
    patchwork::plot_annotation(
        title = "Within-Person (CWC) Bivariate Relationships with Turnover Intention",
        subtitle = "Person-mean centered scores isolate within-person associations"
    )
save_fig(p_cwc_scatter, "eda_26_cwc_scatterplots.svg", width = 12, height = 8)


# --- 6.3 Cross-level scatterplots -------------------------------------------
log_msg("  6.3 Cross-level scatterplots")

person_means_ti <- tbls$l1 |>
    dplyr::group_by(response_id) |>
    dplyr::summarise(
        ti_pmean = mean(turnover_intention_mean, na.rm = TRUE),
        .groups = "drop"
    ) |>
    dplyr::left_join(tbls$l2, by = "response_id")

xlvl_plots <- purrr::map(c("br_mean", "vio_mean", "js_mean"), function(mod) {
    ggplot(person_means_ti, aes(x = .data[[mod]], y = ti_pmean)) +
        geom_point(alpha = 0.2, size = 1) +
        geom_smooth(
            method = "loess",
            color = viridis::viridis(1), se = TRUE
        ) +
        geom_smooth(
            method = "lm",
            color = "red", linetype = "dashed", se = FALSE
        ) +
        labs(
            x = l2_labels[mod] %||% mod,
            y = "Person-Mean Turnover Intention"
        )
})

p_xlvl <- patchwork::wrap_plots(xlvl_plots, ncol = 3) +
    patchwork::plot_annotation(
        title = "Cross-Level: L2 Moderators vs. Person-Mean Turnover Intention",
        subtitle = "Blue = LOESS, Red dashed = linear fit"
    )
save_fig(p_xlvl, "eda_27_crosslevel_scatterplots.svg", width = 14, height = 5)


# --- 6.4 Repeated-measures correlation (rmcorr) key pairs --------------------
log_msg("  6.4 rmcorr key pairs")

rmc_pairs <- list(
    c("pf_mean", "turnover_intention_mean"),
    c("ee_mean", "turnover_intention_mean"),
    c("comp_mean", "turnover_intention_mean"),
    c("auto_mean", "turnover_intention_mean")
)

svg(file.path(FIGS_DIR, "eda_28_rmcorr_key_pairs.svg"),
    width = 12, height = 10
)
par(mfrow = c(2, 2))
for (pair in rmc_pairs) {
    rmc <- rmcorr::rmcorr(
        participant = response_id,
        measure1 = pair[1], measure2 = pair[2],
        dataset = as.data.frame(tbls$l1)
    )
    plot(rmc,
        overall = TRUE, lwd = 2, overall.lwd = 3,
        xlab = pair[1], ylab = pair[2],
        main = glue(
            "rmcorr = {round(rmc$r, 3)}, p = {format.pval(rmc$p, digits = 3)}"
        )
    )
}
dev.off()
log_msg("Saved: ", file.path(FIGS_DIR, "eda_28_rmcorr_key_pairs.svg"))


# --- 6.5 Three-way correlation comparison -----------------------------------
log_msg("  6.5 Correlation comparison table")

# Naive Pearson (ignoring nesting)
naive_corr <- tbls$l1 |>
    dplyr::select(all_of(l1_scale_vars)) |>
    correlation::correlation(method = "pearson") |>
    as.data.frame() |>
    dplyr::select(Parameter1, Parameter2, r_naive = r) |>
    dplyr::mutate(across(c(Parameter1, Parameter2), as.character))

# # Between-person (person means)
# person_means_all <- tbls$l1 |>
#     dplyr::group_by(response_id) |>
#     dplyr::summarise(
#         across(all_of(l1_scale_vars), \(x) mean(x, na.rm = TRUE)),
#         .groups = "drop"
#     )
easystats_corr <- tbls$l1 |>
    # dplyr::select(-response_id) |>
    dplyr::select(-c(timepoint, duration)) |>
    correlation::correlation(multilevel = TRUE) |>
    as.data.frame() |>
    dplyr::select(Parameter1, Parameter2, r_between = r) |>
    dplyr::mutate(across(c(Parameter1, Parameter2), as.character))

# Within-person (rmcorr)
rmc_full <- rmcorr::rmcorr_mat(
    participant = response_id,
    variables = l1_scale_vars,
    dataset = as.data.frame(tbls$l1),
    CI.level = 0.95
)

# Convert rmcorr matrix to long format
rmc_mat_full <- rmc_full$matrix
rmc_long <- as.data.frame(as.table(rmc_mat_full)) |>
    dplyr::rename(Parameter1 = Var1, Parameter2 = Var2, r_within = Freq) |>
    dplyr::mutate(across(c(Parameter1, Parameter2), as.character)) |>
    dplyr::filter(Parameter1 != Parameter2)

# Merge
corr_compare <- naive_corr |>
    dplyr::left_join(easystats_corr, by = c("Parameter1", "Parameter2")) |>
    dplyr::left_join(rmc_long, by = c("Parameter1", "Parameter2")) |>
    dplyr::mutate(across(starts_with("r_"), ~ round(., 3)))

cat("\n=== Three-Way Correlation Comparison ===\n")
print(as.data.frame(corr_compare))

# Save CSV
readr::write_csv(
    corr_compare,
    file.path(FIGS_DIR, "eda_29_correlation_comparison.csv")
)
log_msg("Saved: ", file.path(FIGS_DIR, "eda_29_correlation_comparison.csv"))

# Render as SVG table
cc_grob <- gridExtra::tableGrob(
    corr_compare,
    rows = NULL,
    theme = gridExtra::ttheme_minimal(base_size = 7)
)
pdf(file.path(FIGS_DIR, "eda_29_correlation_comparison.pdf"),
    width = 14, height = 12
)
grid::grid.draw(cc_grob)
dev.off()
log_msg("Saved: ", file.path(FIGS_DIR, "eda_29_correlation_comparison.pdf"))


# =============================================================================
# PHASE 7: PRELIMINARY MULTILEVEL MODEL DIAGNOSTICS
# =============================================================================
log_msg("=== PHASE 7: Preliminary MLM Diagnostics ===")

# --- 7.1 Unconditional means models table ------------------------------------
log_msg("  7.1 Unconditional means models")

ucm_table <- purrr::map_dfr(l1_scale_vars, function(var) {
    fit <- ucm_fits[[var]]
    tidied <- broom.mixed::tidy(fit)
    glanced <- broom.mixed::glance(fit)

    tibble::tibble(
        variable   = var,
        intercept  = round(tidied$estimate[tidied$term == "(Intercept)"], 3),
        aic        = round(glanced$AIC, 1),
        bic        = round(glanced$BIC, 1),
        REML_crit  = round(glanced$REMLcrit, 1)
    )
})

cat("\n=== Unconditional Means Model Summary ===\n")
print(as.data.frame(ucm_table))

# Combine with ICC results for a complete summary
ucm_full <- ucm_table |>
    dplyr::left_join(
        icc_results |> dplyr::select(variable, icc_adjusted, var_between, var_within),
        by = "variable"
    ) |>
    dplyr::mutate(across(where(is.numeric), ~ round(., 3)))

ucm_grob <- gridExtra::tableGrob(
    ucm_full,
    rows = NULL,
    theme = gridExtra::ttheme_minimal(base_size = 8)
)
pdf(file.path(FIGS_DIR, "eda_30_unconditional_means_table.pdf"),
    width = 14, height = 5
)
grid::grid.draw(ucm_grob)
dev.off()
log_msg("Saved: ", file.path(FIGS_DIR, "eda_30_unconditional_means_table.pdf"))


# --- 7.2 Unconditional growth models ----------------------------------------
log_msg("  7.2 Unconditional growth models")

tbls$l1$time_c <- tbls$l1$timepoint - 1 # center: 0, 1, 2

ugm_results <- purrr::map_dfr(l1_scale_vars, function(var) {
    f_ucm <- as.formula(paste(var, "~ 1 + (1 | response_id)"))
    f_ugm <- as.formula(paste(var, "~ time_c + (time_c | response_id)"))

    fit_ucm <- lme4::lmer(f_ucm, data = tbls$l1, REML = FALSE)
    fit_ugm <- tryCatch(
        lme4::lmer(f_ugm, data = tbls$l1, REML = FALSE),
        error = function(e) NULL,
        warning = function(w) {
            suppressWarnings(lme4::lmer(f_ugm, data = tbls$l1, REML = FALSE))
        }
    )

    if (!is.null(fit_ugm)) {
        lrt <- anova(fit_ucm, fit_ugm)
        tibble::tibble(
            variable     = var,
            time_fixed   = round(fixef(fit_ugm)["time_c"], 3),
            lrt_chisq    = round(lrt$Chisq[2], 2),
            lrt_df       = lrt$Df[2],
            lrt_p        = round(lrt$`Pr(>Chisq)`[2], 4),
            converged    = TRUE
        )
    } else {
        # Fallback: fixed effect only
        f_ugm_fe <- as.formula(paste(var, "~ time_c + (1 | response_id)"))
        fit_ugm_fe <- lme4::lmer(f_ugm_fe, data = tbls$l1, REML = FALSE)
        lrt <- anova(fit_ucm, fit_ugm_fe)
        tibble::tibble(
            variable     = var,
            time_fixed   = round(fixef(fit_ugm_fe)["time_c"], 3),
            lrt_chisq    = round(lrt$Chisq[2], 2),
            lrt_df       = lrt$Df[2],
            lrt_p        = round(lrt$`Pr(>Chisq)`[2], 4),
            converged    = FALSE
        )
    }
})

cat("\n=== Unconditional Growth Models ===\n")
print(as.data.frame(ugm_results))

ugm_grob <- gridExtra::tableGrob(
    ugm_results,
    rows = NULL,
    theme = gridExtra::ttheme_minimal(base_size = 9)
)
pdf(file.path(FIGS_DIR, "eda_31_unconditional_growth_comparison.pdf"),
    width = 12, height = 5
)
grid::grid.draw(ugm_grob)
dev.off()
log_msg("Saved: ", file.path(FIGS_DIR, "eda_31_unconditional_growth_comparison.pdf"))


# --- 7.3 Residual diagnostics -----------------------------------------------
log_msg("  7.3 Residual diagnostics")

fit_ti <- ucm_fits[["turnover_intention_mean"]]

diag_data <- tibble::tibble(
    fitted   = fitted(fit_ti),
    resid_l1 = residuals(fit_ti)
)
ri_vals <- ranef(fit_ti)$response_id[, 1]

p_qq_l1 <- ggplot(diag_data, aes(sample = resid_l1)) +
    stat_qq(alpha = 0.3) +
    stat_qq_line(color = "red") +
    labs(title = "L1 Residual QQ Plot")

p_resid_fit <- ggplot(diag_data, aes(x = fitted, y = resid_l1)) +
    geom_point(alpha = 0.1) +
    geom_hline(yintercept = 0, linetype = "dashed") +
    geom_smooth(method = "loess", color = "red", se = FALSE) +
    labs(title = "L1 Residuals vs. Fitted", x = "Fitted", y = "Residuals")

p_qq_l2 <- ggplot(tibble::tibble(ri = ri_vals), aes(sample = ri)) +
    stat_qq(alpha = 0.3) +
    stat_qq_line(color = "red") +
    labs(title = "L2 Random Intercept QQ Plot")

p_scale_loc <- ggplot(diag_data, aes(
    x = fitted,
    y = sqrt(abs(resid_l1))
)) +
    geom_point(alpha = 0.1) +
    geom_smooth(method = "loess", color = "red", se = FALSE) +
    labs(
        title = "Scale-Location Plot",
        x = "Fitted", y = "sqrt(|Residuals|)"
    )

p_resid <- (p_qq_l1 + p_resid_fit) / (p_qq_l2 + p_scale_loc) +
    patchwork::plot_annotation(
        title = "Residual Diagnostics: Turnover Intention (Unconditional Means)"
    )
save_fig(p_resid, "eda_32_residual_diagnostics_ti.svg", width = 10, height = 10)


# --- 7.4 Influence diagnostics ----------------------------------------------
log_msg("  7.4 Influence diagnostics")

# Simple bivariate model for influence check
fit_ti_biv <- lme4::lmer(
    turnover_intention_mean ~ pf_mean + (1 | response_id),
    data = tbls$l1, REML = TRUE
)

p_influence <- tryCatch(
    {
        outlier_check <- performance::check_outliers(fit_ti_biv, method = "cook")
        plot(outlier_check) +
            labs(title = "Influence Diagnostics: Cook's Distance (PF → TI)")
    },
    error = function(e) {
        # Fallback: manual Cook's D via residuals
        cooks_d <- cooks.distance(fit_ti_biv)
        ggplot(
            tibble::tibble(obs = seq_along(cooks_d), cooksd = cooks_d),
            aes(x = obs, y = cooksd)
        ) +
            geom_point(alpha = 0.3) +
            geom_hline(
                yintercept = 4 / nrow(tbls$l1),
                linetype = "dashed",
                color = "red"
            ) +
            labs(
                title = "Cook's Distance (PF → TI)",
                x = "Observation", y = "Cook's Distance"
            )
    }
)
save_fig(p_influence, "eda_33_influence_diagnostics.svg")


# =============================================================================
# PHASE 8: CROSS-LEVEL INTERACTION EXPLORATION
# =============================================================================
log_msg("=== PHASE 8: Cross-Level Interaction Exploration ===")

# --- 8.1 Slope-as-outcome visualization -------------------------------------
log_msg("  8.1 Slope-as-outcome")

l1_preds <- c("pf_mean", "cw_mean", "ee_mean", "comp_mean", "auto_mean", "relt_mean")
l2_mods <- c("br_mean", "vio_mean", "js_mean")

# Compute person-level slopes
person_slopes <- tbls$l1 |>
    dplyr::group_by(response_id) |>
    dplyr::summarise(
        slope_pf   = coef(lm(turnover_intention_mean ~ pf_mean))[2],
        slope_cw   = coef(lm(turnover_intention_mean ~ cw_mean))[2],
        slope_ee   = coef(lm(turnover_intention_mean ~ ee_mean))[2],
        slope_comp = coef(lm(turnover_intention_mean ~ comp_mean))[2],
        slope_auto = coef(lm(turnover_intention_mean ~ auto_mean))[2],
        slope_relt = coef(lm(turnover_intention_mean ~ relt_mean))[2],
        .groups = "drop"
    ) |>
    dplyr::left_join(tbls$l2, by = "response_id")

slope_cols <- c("slope_pf", "slope_cw", "slope_ee", "slope_comp", "slope_auto", "slope_relt")

sao_plots <- list()
for (mod in l2_mods) {
    for (s in slope_cols) {
        pred_name <- stringr::str_remove(s, "slope_")
        sao_plots[[paste(mod, s, sep = "_x_")]] <-
            ggplot(person_slopes, aes(x = .data[[mod]], y = .data[[s]])) +
            geom_point(alpha = 0.15, size = 0.8) +
            geom_smooth(method = "lm",
                        color = viridis::viridis(1), se = TRUE) +
            geom_hline(yintercept = 0, linetype = "dashed") +
            labs(
                x = l2_labels[mod] %||% mod,
                y = paste0("slope(", pred_name, "→TI)")
            )
    }
}

p_sao <- patchwork::wrap_plots(sao_plots, ncol = 3) +
    patchwork::plot_annotation(
        title = "Slope-as-Outcome: Within-Person Slopes vs. L2 Moderators",
        subtitle = "Each point = one person's OLS slope of L1 predictor → TI"
    )
save_fig(p_sao, "eda_34_slope_as_outcome.svg", width = 14, height = 16)


# --- 8.2 Conditional means panels (simple slopes preview) --------------------
log_msg("  8.2 Conditional slopes")

# Create tertile splits for moderators
tbls$full <- tbls$full |>
    dplyr::mutate(
        br_tertile = dplyr::ntile(br_mean, 3),
        vio_tertile = dplyr::ntile(vio_mean, 3),
        js_tertile = dplyr::ntile(js_mean, 3)
    ) |>
    dplyr::mutate(across(
        ends_with("_tertile"),
        ~ factor(., labels = c("Low", "Medium", "High"))
    ))

# Helper for conditional slope panels
make_cond_panel <- function(data, l1_preds, moderator_col, mod_label) {
    plots <- purrr::map(l1_preds, function(pred) {
        ggplot(data, aes(
            x = .data[[pred]], y = turnover_intention_mean,
            color = .data[[moderator_col]]
        )) +
            geom_point(alpha = 0.05, size = 0.3) +
            geom_smooth(method = "lm", se = TRUE) +
            scale_color_viridis_d(name = mod_label, end = 0.85) +
            labs(x = pred, y = "Turnover Intention")
    })
    patchwork::wrap_plots(plots, ncol = 3) +
        patchwork::plot_annotation(
            title = glue("L1 Predictors → TI, Moderated by {mod_label}")
        )
}

p_cond_br <- make_cond_panel(
    tbls$full, l1_preds, "br_tertile", "Breach Level"
)
save_fig(p_cond_br, "eda_35_conditional_slopes_breach.svg",
    width = 14, height = 10
)

p_cond_vio <- make_cond_panel(
    tbls$full, l1_preds, "vio_tertile", "Violation Level"
)
save_fig(p_cond_vio, "eda_36_conditional_slopes_violation.svg",
    width = 14, height = 10
)

p_cond_js <- make_cond_panel(
    tbls$full, l1_preds, "js_tertile", "Job Satisfaction Level"
)
save_fig(p_cond_js, "eda_37_conditional_slopes_js.svg",
    width = 14, height = 10
)


# --- 8.3 Interaction heatmap ------------------------------------------------
log_msg("  8.3 Interaction heatmap")

# Correlations between person-level slopes and L2 moderators
heat_mat <- cor(
    person_slopes[, slope_cols],
    person_slopes[, l2_mods],
    use = "complete.obs"
)
rownames(heat_mat) <- stringr::str_remove(slope_cols, "slope_")

svg(file.path(FIGS_DIR, "eda_38_interaction_heatmap.svg"),
    width = 8, height = 6
)
corrplot::corrplot(heat_mat,
    method = "color", is.corr = TRUE,
    addCoef.col = "black", number.cex = 0.9,
    tl.col = "black", cl.pos = "b",
    title = "Cross-Level Interaction Preview:\ncor(Person-Slope, L2 Moderator)",
    mar = c(0, 0, 3, 0)
)
dev.off()
log_msg("Saved: ", file.path(FIGS_DIR, "eda_38_interaction_heatmap.svg"))


# =============================================================================
# SUMMARY
# =============================================================================
log_msg("=== EDA COMPLETE ===")
log_msg("Output directory: ", FIGS_DIR)
log_msg("Total SVGs generated: 32 (figures)")
log_msg("Total PDFs generated: 6 (tables)")
log_msg("Total CSVs generated: 2")
cat("\n=== File Listing ===\n")
list.files(FIGS_DIR, pattern = "\\.(svg|pdf|csv)$") |> sort() |> cat(sep = "\n")
