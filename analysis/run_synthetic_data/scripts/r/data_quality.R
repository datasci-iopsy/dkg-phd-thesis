#!/usr/bin/env Rscript
# =============================================================================
# analysis/run_synthetic_data/scripts/r/data_quality.R
#
# Careless responding detection and data quality screening for the synthetic
# panel dataset using the careless package (Yentes & Wilhelm, 2018).
#
# Four screening indices applied at the person level:
#   1. Longstring  — maximum run of identical responses per timepoint (L1) and
#                    for the L2 intake item block
#   2. IRV         — intra-individual response variability per timepoint
#   3. Mahalanobis — multivariate outlier detection on person-level scale means
#   4. Duration    — survey completion time per timepoint
#
# Exclusion rule: participants flagged by >= 2 criteria are removed. Individual
# criterion flags are retained in the diagnostic summary regardless.
#
# Input:  data/export/syn_qualtrics_fct_panel_responses_YYYYMMDD.csv
#           (most recent file without "cleaned" in the name)
# Output: data/export/syn_qualtrics_fct_panel_responses_cleaned_YYYYMMDD.csv
#         figs/data_quality/ — diagnostic SVGs and CSV screening summary
#
# References:
#   Yentes & Wilhelm (2018). The careless R package: Bad data before bad
#     analyses. Practical Assessment, Research & Evaluation, 23(2).
#   Curran (2016). Methods for the detection of carelessly invalid responses
#     in self-report inventories. Journal of Experimental Social Psychology, 66.
# =============================================================================

# --- [0] Libraries and setup -------------------------------------------------
library(careless)
library(ggplot2)
library(patchwork)
library(dplyr)
library(tidyr)
library(readr)
library(tibble)
library(stringr)
library(here)

options(tibble.width = Inf)

# Source shared utilities (log_msg, ensure_dir, save_svg)
source(here::here("analysis", "shared", "utils", "common_utils.r"))
source(here::here("analysis", "shared", "utils", "plot_utils.r"))

FIGS_DIR <- here::here("analysis", "run_synthetic_data", "figs", "data_quality")
ensure_dir(FIGS_DIR)

EXPORT_DIR <- here::here("analysis", "run_synthetic_data", "data", "export")

today <- format(Sys.Date(), "%Y%m%d")

theme_set(theme_apa)

# SVG save helper (binds FIGS_DIR)
save_fig <- function(plot, filename, width = 10, height = 6) {
    save_svg(plot, file.path(FIGS_DIR, filename), width, height)
}

# ---------------------------------------------------------------------------
# Screening thresholds (adjust here to change criteria globally)
# ---------------------------------------------------------------------------
THRESH_LONGSTRING_L1 <- 10L   # max run of identical L1 responses (out of 30)
THRESH_LONGSTRING_L2 <- 10L   # max run of identical L2 responses (out of 20)
THRESH_IRV_L1        <- 0.50  # min SD across L1 items per timepoint
THRESH_IRV_L2        <- 0.25  # min SD across L2 intake items
THRESH_DURATION_SECS <- 90L   # min seconds for a valid followup timepoint
THRESH_MAHAD_CONF    <- 0.999 # chi-squared confidence for Mahalanobis cutoff
MIN_FLAGS_TO_EXCLUDE <- 2L    # number of criteria that must be flagged for exclusion

log_msg("=== DATA QUALITY SCREENING ===")
log_msg("Output directory: ", FIGS_DIR)
log_msg("Thresholds:")
log_msg("  Longstring L1 > ", THRESH_LONGSTRING_L1, " (of 30 items)")
log_msg("  Longstring L2 > ", THRESH_LONGSTRING_L2, " (of 20 items)")
log_msg("  IRV L1 < ", THRESH_IRV_L1)
log_msg("  IRV L2 < ", THRESH_IRV_L2)
log_msg("  Duration < ", THRESH_DURATION_SECS, " seconds")
log_msg("  Mahalanobis confidence: ", THRESH_MAHAD_CONF)
log_msg("  Exclusion rule: >= ", MIN_FLAGS_TO_EXCLUDE, " criteria flagged")


# =============================================================================
# [1] DATA LOADING
# =============================================================================
log_msg("=== [1] Loading data ===")

# Load the most recent raw export (exclude any already-cleaned file)
raw_files <- list.files(
    EXPORT_DIR,
    pattern = "^syn_qualtrics_fct_panel_responses_\\d{8}\\.csv$",
    full.names = TRUE
)
if (length(raw_files) == 0) {
    stop(
        "No raw panel CSV found in data/export/. ",
        "Expected: syn_qualtrics_fct_panel_responses_YYYYMMDD.csv"
    )
}
input_path <- sort(raw_files, decreasing = TRUE)[1]
log_msg("Loading: ", basename(input_path))

df_raw <- readr::read_csv(input_path, show_col_types = FALSE)
log_msg("Loaded: ", nrow(df_raw), " rows x ", ncol(df_raw), " columns")
n_participants <- dplyr::n_distinct(df_raw$response_id)
log_msg("Participants (L2): ", n_participants)


# =============================================================================
# [2] ITEM COLUMN DEFINITIONS
# =============================================================================
log_msg("=== [2] Defining item blocks ===")

# L1 items: time-varying, one set per followup timepoint (30 items)
l1_item_cols <- c(
    paste0("pf",   1:6),   # physical fatigue (burnout)
    paste0("cw",   1:5),   # cognitive weariness (burnout)
    paste0("ee",   1:3),   # emotional exhaustion (burnout)
    paste0("comp", 1:4),   # competence frustration
    paste0("auto", 1:4),   # autonomy frustration
    paste0("relt", 1:4),   # relatedness frustration
    "atcb2", "atcb5", "atcb6", "atcb7"  # turnover intentions
)

# L2 items: time-invariant, from intake survey (20 items)
l2_item_cols <- c(
    paste0("pa",  1:5),  # positive affect
    paste0("na",  1:5),  # negative affect
    paste0("br",  1:5),  # psychological contract breach
    paste0("vio", 1:4),  # contract violation
    "js1"                # job satisfaction (single item)
)

# Verify all columns exist in the data
missing_l1 <- setdiff(l1_item_cols, names(df_raw))
missing_l2 <- setdiff(l2_item_cols, names(df_raw))
if (length(missing_l1) > 0) {
    stop("Missing L1 item columns: ", paste(missing_l1, collapse = ", "))
}
if (length(missing_l2) > 0) {
    stop("Missing L2 item columns: ", paste(missing_l2, collapse = ", "))
}
log_msg("L1 item block: ", length(l1_item_cols), " items")
log_msg("L2 item block: ", length(l2_item_cols), " items")


# =============================================================================
# [3] LONGSTRING AND IRV (per timepoint, L1 items)
# =============================================================================
log_msg("=== [3] Longstring and IRV — L1 items per timepoint ===")

#' Compute careless indices for one timepoint slice
#'
#' @param df Data frame subset for a single timepoint.
#' @param item_cols Character vector of item column names.
#' @return Tibble with response_id, longstring, and irv.
compute_l1_indices <- function(df, item_cols) {
    items_mat <- as.matrix(df[, item_cols])
    tibble::tibble(
        response_id = df$response_id,
        timepoint   = df$timepoint,
        duration    = df$duration,
        longstring  = careless::longstring(items_mat),
        irv         = careless::irv(items_mat)
    )
}

l1_indices <- df_raw |>
    dplyr::group_by(timepoint) |>
    dplyr::group_split() |>
    lapply(compute_l1_indices, item_cols = l1_item_cols) |>
    dplyr::bind_rows()

log_msg("L1 indices computed across ", dplyr::n_distinct(l1_indices$timepoint), " timepoints")


# =============================================================================
# [4] LONGSTRING AND IRV (L2 items, one row per participant)
# =============================================================================
log_msg("=== [4] Longstring and IRV — L2 intake item block ===")

df_l2_items <- df_raw |>
    dplyr::distinct(response_id, .keep_all = TRUE) |>
    dplyr::select(dplyr::all_of(c("response_id", l2_item_cols)))

l2_mat <- as.matrix(df_l2_items[, l2_item_cols])

l2_indices <- tibble::tibble(
    response_id      = df_l2_items$response_id,
    longstring_l2    = careless::longstring(l2_mat),
    irv_l2           = careless::irv(l2_mat)
)

log_msg("L2 indices computed for ", nrow(l2_indices), " participants")


# =============================================================================
# [5] MAHALANOBIS DISTANCE (person level, scale means)
# =============================================================================
log_msg("=== [5] Mahalanobis distance — person-level scale means ===")

# Aggregate L1 scale means to person level (mean across timepoints)
l1_scale_means <- df_raw |>
    dplyr::group_by(response_id) |>
    dplyr::summarise(
        pf_mean_pm   = mean(pf_mean,   na.rm = TRUE),
        cw_mean_pm   = mean(cw_mean,   na.rm = TRUE),
        ee_mean_pm   = mean(ee_mean,   na.rm = TRUE),
        comp_mean_pm = mean(comp_mean, na.rm = TRUE),
        auto_mean_pm = mean(auto_mean, na.rm = TRUE),
        relt_mean_pm = mean(relt_mean, na.rm = TRUE),
        atcb_mean_pm = mean(atcb_mean, na.rm = TRUE),
        ti_mean_pm   = mean(turnover_intention_mean, na.rm = TRUE),
        .groups = "drop"
    )

# L2 scale means (constant per person; take first row)
l2_scale_means <- df_raw |>
    dplyr::distinct(response_id, .keep_all = TRUE) |>
    dplyr::select(response_id, pa_mean, na_mean, br_mean, vio_mean, js_mean)

# Combined person-level matrix for Mahalanobis
mahad_df <- l2_scale_means |>
    dplyr::left_join(l1_scale_means, by = "response_id")

mahad_vars <- setdiff(names(mahad_df), "response_id")
mahad_mat  <- as.matrix(mahad_df[, mahad_vars])

mahad_dist   <- careless::mahad(mahad_mat)
mahad_cutoff <- qchisq(THRESH_MAHAD_CONF, df = ncol(mahad_mat))

mahad_indices <- tibble::tibble(
    response_id  = mahad_df$response_id,
    mahad_dist   = mahad_dist,
    mahad_cutoff = mahad_cutoff,
    flag_mahad   = mahad_dist > mahad_cutoff
)

log_msg(
    "Mahalanobis: cutoff = ", round(mahad_cutoff, 2),
    " (chi-sq df=", ncol(mahad_mat), ", p=", THRESH_MAHAD_CONF, ")"
)
log_msg("Mahalanobis flagged: ", sum(mahad_indices$flag_mahad), " participants")


# =============================================================================
# [6] PERSON-LEVEL AGGREGATION AND FLAGS
# =============================================================================
log_msg("=== [6] Aggregating to person level and applying flags ===")

# Per-person summaries across timepoints
l1_person <- l1_indices |>
    dplyr::group_by(response_id) |>
    dplyr::summarise(
        longstring_l1_max  = max(longstring),
        irv_l1_min         = min(irv),
        duration_min_secs  = min(duration),
        .groups = "drop"
    )

# Combine all indices
screening <- l1_person |>
    dplyr::left_join(l2_indices,    by = "response_id") |>
    dplyr::left_join(mahad_indices, by = "response_id") |>
    dplyr::mutate(
        flag_longstring_l1 = longstring_l1_max  > THRESH_LONGSTRING_L1,
        flag_longstring_l2 = longstring_l2      > THRESH_LONGSTRING_L2,
        flag_irv_l1        = irv_l1_min         < THRESH_IRV_L1,
        flag_irv_l2        = irv_l2             < THRESH_IRV_L2,
        flag_duration      = duration_min_secs  < THRESH_DURATION_SECS,
        n_flags = rowSums(dplyr::pick(
            flag_longstring_l1, flag_longstring_l2,
            flag_irv_l1, flag_irv_l2,
            flag_duration, flag_mahad
        ), na.rm = TRUE),
        exclude = n_flags >= MIN_FLAGS_TO_EXCLUDE
    )

n_flagged  <- sum(screening$n_flags >= 1L)
n_excluded <- sum(screening$exclude)
log_msg("Participants with >= 1 flag: ", n_flagged)
log_msg("Participants excluded (>= ", MIN_FLAGS_TO_EXCLUDE, " flags): ", n_excluded)
log_msg("Participants retained: ", n_participants - n_excluded)

# Per-criterion counts
criterion_counts <- tibble::tibble(
    criterion = c(
        "Longstring L1", "Longstring L2",
        "IRV L1", "IRV L2",
        "Duration", "Mahalanobis"
    ),
    n_flagged = c(
        sum(screening$flag_longstring_l1),
        sum(screening$flag_longstring_l2),
        sum(screening$flag_irv_l1),
        sum(screening$flag_irv_l2),
        sum(screening$flag_duration),
        sum(screening$flag_mahad)
    )
)
log_msg("Per-criterion flag counts:")
for (i in seq_len(nrow(criterion_counts))) {
    log_msg("  ", criterion_counts$criterion[i], ": ", criterion_counts$n_flagged[i])
}


# =============================================================================
# [7] DIAGNOSTIC FIGURES
# =============================================================================
log_msg("=== [7] Generating diagnostic figures ===")

# --- [7a] Longstring distributions ------------------------------------------
p_ls_l1 <- ggplot(l1_person, aes(x = longstring_l1_max)) +
    geom_histogram(binwidth = 1, fill = "#2c7bb6", color = "white", alpha = 0.85) +
    geom_vline(xintercept = THRESH_LONGSTRING_L1 + 0.5, color = "#d7191c",
               linetype = "dashed", linewidth = 0.8) +
    labs(
        title = "L1 Longstring (max across timepoints)",
        subtitle = paste0("Flag threshold: > ", THRESH_LONGSTRING_L1,
                          " | Flagged: ", sum(screening$flag_longstring_l1)),
        x = "Max consecutive identical responses",
        y = "Count"
    )

p_ls_l2 <- ggplot(l2_indices, aes(x = longstring_l2)) +
    geom_histogram(binwidth = 1, fill = "#1a9641", color = "white", alpha = 0.85) +
    geom_vline(xintercept = THRESH_LONGSTRING_L2 + 0.5, color = "#d7191c",
               linetype = "dashed", linewidth = 0.8) +
    labs(
        title = "L2 Longstring (intake item block)",
        subtitle = paste0("Flag threshold: > ", THRESH_LONGSTRING_L2,
                          " | Flagged: ", sum(screening$flag_longstring_l2)),
        x = "Max consecutive identical responses",
        y = "Count"
    )

save_fig(
    p_ls_l1 / p_ls_l2,
    paste0("dq_01_longstring_distribution_", today, ".svg"),
    width = 10, height = 8
)

# --- [7b] IRV distributions --------------------------------------------------
p_irv_l1 <- ggplot(l1_person, aes(x = irv_l1_min)) +
    geom_histogram(bins = 30, fill = "#2c7bb6", color = "white", alpha = 0.85) +
    geom_vline(xintercept = THRESH_IRV_L1, color = "#d7191c",
               linetype = "dashed", linewidth = 0.8) +
    labs(
        title = "L1 IRV (minimum across timepoints)",
        subtitle = paste0("Flag threshold: < ", THRESH_IRV_L1,
                          " | Flagged: ", sum(screening$flag_irv_l1)),
        x = "Intra-individual response variability (SD)",
        y = "Count"
    )

p_irv_l2 <- ggplot(l2_indices, aes(x = irv_l2)) +
    geom_histogram(bins = 30, fill = "#1a9641", color = "white", alpha = 0.85) +
    geom_vline(xintercept = THRESH_IRV_L2, color = "#d7191c",
               linetype = "dashed", linewidth = 0.8) +
    labs(
        title = "L2 IRV (intake item block)",
        subtitle = paste0("Flag threshold: < ", THRESH_IRV_L2,
                          " | Flagged: ", sum(screening$flag_irv_l2)),
        x = "Intra-individual response variability (SD)",
        y = "Count"
    )

save_fig(
    p_irv_l1 / p_irv_l2,
    paste0("dq_02_irv_distribution_", today, ".svg"),
    width = 10, height = 8
)

# --- [7c] Duration distributions per timepoint --------------------------------
p_dur <- ggplot(l1_indices, aes(x = duration, fill = factor(timepoint))) +
    geom_histogram(bins = 40, alpha = 0.75, position = "identity") +
    geom_vline(xintercept = THRESH_DURATION_SECS, color = "#d7191c",
               linetype = "dashed", linewidth = 0.8) +
    scale_fill_viridis_d(option = "D", end = 0.85, name = "Timepoint") +
    labs(
        title = "Survey duration by timepoint",
        subtitle = paste0(
            "Flag threshold: < ", THRESH_DURATION_SECS, " seconds",
            " | Flagged participants: ", sum(screening$flag_duration)
        ),
        x = "Duration (seconds)",
        y = "Count"
    )

save_fig(
    p_dur,
    paste0("dq_03_duration_distribution_", today, ".svg"),
    width = 10, height = 6
)

# --- [7d] Mahalanobis distance -----------------------------------------------
mahad_plot_df <- mahad_indices |>
    dplyr::arrange(mahad_dist) |>
    dplyr::mutate(rank = seq_len(dplyr::n()))

p_mahad <- ggplot(mahad_plot_df, aes(x = rank, y = mahad_dist, color = flag_mahad)) +
    geom_point(alpha = 0.6, size = 1.2) +
    geom_hline(yintercept = mahad_cutoff, color = "#d7191c",
               linetype = "dashed", linewidth = 0.8) +
    scale_color_manual(
        values = c("FALSE" = "#2c7bb6", "TRUE" = "#d7191c"),
        labels = c("Retained", "Flagged"),
        name = NULL
    ) +
    labs(
        title = "Mahalanobis distance (person-level scale means)",
        subtitle = paste0(
            "Cutoff: ", round(mahad_cutoff, 1),
            " (chi-sq df=", ncol(mahad_mat), ", p=", THRESH_MAHAD_CONF, ")",
            " | Flagged: ", sum(screening$flag_mahad)
        ),
        x = "Participant rank",
        y = "Mahalanobis distance"
    )

save_fig(
    p_mahad,
    paste0("dq_04_mahalanobis_", today, ".svg"),
    width = 10, height = 6
)

# --- [7e] Flag summary -------------------------------------------------------
flag_summary_long <- criterion_counts |>
    dplyr::mutate(criterion = factor(criterion, levels = criterion))

p_flags <- ggplot(flag_summary_long, aes(x = criterion, y = n_flagged)) +
    geom_col(fill = "#2c7bb6", alpha = 0.85, width = 0.6) +
    geom_text(aes(label = n_flagged), vjust = -0.4, size = 3.5) +
    labs(
        title = "Participants flagged per screening criterion",
        subtitle = paste0(
            "N total = ", n_participants,
            " | Excluded (>= ", MIN_FLAGS_TO_EXCLUDE, " flags) = ", n_excluded
        ),
        x = NULL,
        y = "Count"
    ) +
    theme(axis.text.x = element_text(angle = 30, hjust = 1))

# Multi-flag distribution
flag_dist <- screening |>
    dplyr::count(n_flags) |>
    dplyr::mutate(
        excluded = n_flags >= MIN_FLAGS_TO_EXCLUDE,
        label    = ifelse(excluded, paste0(n_flags, " (excluded)"), as.character(n_flags))
    )

p_nflags <- ggplot(flag_dist, aes(x = factor(n_flags), y = n, fill = excluded)) +
    geom_col(width = 0.6, alpha = 0.85) +
    geom_text(aes(label = n), vjust = -0.4, size = 3.5) +
    scale_fill_manual(
        values = c("FALSE" = "#2c7bb6", "TRUE" = "#d7191c"),
        labels = c("Retained", "Excluded"),
        name = NULL
    ) +
    labs(
        title = "Distribution of flag counts per participant",
        x = "Number of criteria flagged",
        y = "Count"
    )

save_fig(
    p_flags / p_nflags,
    paste0("dq_05_flag_summary_", today, ".svg"),
    width = 10, height = 9
)

log_msg("Diagnostic figures saved to: ", FIGS_DIR)


# =============================================================================
# [8] SCREENING SUMMARY TABLE
# =============================================================================
log_msg("=== [8] Writing screening summary ===")

summary_path <- file.path(FIGS_DIR, paste0("dq_06_screening_summary_", today, ".csv"))
readr::write_csv(screening, summary_path)
log_msg("Screening summary: ", summary_path)

excluded_ids <- screening |>
    dplyr::filter(exclude) |>
    dplyr::select(
        response_id, n_flags,
        flag_longstring_l1, flag_longstring_l2,
        flag_irv_l1, flag_irv_l2,
        flag_duration, flag_mahad,
        longstring_l1_max, longstring_l2, irv_l1_min, irv_l2,
        duration_min_secs, mahad_dist
    )

excluded_path <- file.path(FIGS_DIR, paste0("dq_07_excluded_participants_", today, ".csv"))
readr::write_csv(excluded_ids, excluded_path)
log_msg("Excluded participants (", nrow(excluded_ids), "): ", excluded_path)


# =============================================================================
# [9] EXPORT CLEANED DATA
# =============================================================================
log_msg("=== [9] Writing cleaned dataset ===")

retained_ids <- screening |>
    dplyr::filter(!exclude) |>
    dplyr::pull(response_id)

df_cleaned <- df_raw |>
    dplyr::filter(response_id %in% retained_ids)

cleaned_path <- file.path(
    EXPORT_DIR,
    paste0("syn_qualtrics_fct_panel_responses_cleaned_", today, ".csv")
)

readr::write_csv(df_cleaned, cleaned_path)

log_msg("Cleaned dataset written: ", basename(cleaned_path))
log_msg("  Original: ", nrow(df_raw), " rows, ", dplyr::n_distinct(df_raw$response_id), " participants")
log_msg("  Cleaned:  ", nrow(df_cleaned), " rows, ", dplyr::n_distinct(df_cleaned$response_id), " participants")
log_msg("  Excluded: ", n_excluded, " participants")
log_msg("=== DATA QUALITY SCREENING COMPLETE ===")
