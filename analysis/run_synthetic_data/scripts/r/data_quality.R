#!/usr/bin/env Rscript
# =============================================================================
# analysis/run_synthetic_data/scripts/r/data_quality.R
#
# Careless responding detection and data quality screening for the synthetic
# panel dataset using the careless package (Yentes & Wilhelm, 2018).
#
# This is a repeated-measures design (3 within-day surveys per participant).
# L1 indices are computed for each survey independently, allowing detection of
# careless responding that appears only in a specific survey. L2 (intake)
# indices are computed once per participant. All L1 diagnostic figures are
# faceted by survey; L2 figures use a single-panel layout.
#
# Four screening criteria, evaluated at the person level for exclusion:
#   1. Longstring L1  — max run of identical responses within a survey (30 items)
#   2. Longstring L2  — max run of identical responses in the intake block (20 items)
#   3. IRV L1         — intra-individual response variability within a survey
#   4. IRV L2         — intra-individual response variability in the intake block
#   5. Duration       — survey completion time
#   6. Mahalanobis    — multivariate outlier flag (L1 per-survey + L2 per-person)
#
# Person-level exclusion: flagged by >= 2 criteria (any criterion is TRUE if
# it triggered on any survey). Per-survey detail is preserved in the output.
#
# Input:  data/export/syn_qualtrics_fct_panel_responses_YYYYMMDD.csv
# Output: data/export/syn_qualtrics_fct_panel_responses_cleaned_YYYYMMDD.csv
#         figs/data_quality/ — diagnostic SVGs + CSV screening tables
#
# References:
#   Yentes & Wilhelm (2018). The careless R package.
#     Practical Assessment, Research & Evaluation, 23(2).
#   Curran (2016). Methods for the detection of carelessly invalid responses.
#     Journal of Experimental Social Psychology, 66.
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

# SVG save helper (binds FIGS_DIR; no timestamp — script overwrites on each run)
save_fig <- make_save_fig(FIGS_DIR, default_height = 6)

# Survey label helper: converts integer timepoint to readable label
survey_label <- function(tp) paste0("Survey ", tp)

# Shared facet strip theme used across L1 figures
facet_theme <- theme(
    strip.text       = element_text(face = "bold", size = 10),
    strip.background = element_rect(fill = "#f0f0f0", color = NA)
)

# ---------------------------------------------------------------------------
# Screening thresholds (modify here to change criteria globally)
# ---------------------------------------------------------------------------
THRESH_LONGSTRING_L1 <- 10L   # flag if > 10 of 30 L1 items identical in a run
THRESH_LONGSTRING_L2 <- 10L   # flag if > 10 of 20 L2 items identical in a run
THRESH_IRV_L1        <- 0.50  # flag if SD of L1 item responses < 0.50
THRESH_IRV_L2        <- 0.25  # flag if SD of L2 item responses < 0.25
THRESH_DURATION_SECS <- 90L   # flag if survey duration < 90 seconds
THRESH_MAHAD_CONF    <- 0.999 # chi-squared confidence for Mahalanobis cutoff
MIN_FLAGS_TO_EXCLUDE <- 2L    # exclude if >= 2 person-level criteria flagged

log_msg("=== DATA QUALITY SCREENING ===")
log_msg("Output directory: ", FIGS_DIR)
log_msg("Thresholds:")
log_msg("  Longstring L1 > ", THRESH_LONGSTRING_L1, " (of 30 items per survey)")
log_msg("  Longstring L2 > ", THRESH_LONGSTRING_L2, " (of 20 items, intake block)")
log_msg("  IRV L1 < ", THRESH_IRV_L1)
log_msg("  IRV L2 < ", THRESH_IRV_L2)
log_msg("  Duration < ", THRESH_DURATION_SECS, " seconds")
log_msg("  Mahalanobis confidence: ", THRESH_MAHAD_CONF)
log_msg("  Exclusion rule: >= ", MIN_FLAGS_TO_EXCLUDE, " criteria flagged at person level")


# =============================================================================
# [1] DATA LOADING
# =============================================================================
log_msg("=== [1] Loading data ===")

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
n_surveys      <- dplyr::n_distinct(df_raw$timepoint)
log_msg("Participants (L2): ", n_participants)
log_msg("Surveys per participant (L1): ", n_surveys)


# =============================================================================
# [2] ITEM COLUMN DEFINITIONS
# =============================================================================
log_msg("=== [2] Defining item blocks ===")

# L1 items: from followup surveys, vary across surveys (30 items total)
l1_item_cols <- c(
    paste0("pf",   1:6),              # physical fatigue (burnout)
    paste0("cw",   1:5),              # cognitive weariness (burnout)
    paste0("ee",   1:3),              # emotional exhaustion (burnout)
    paste0("comp", 1:4),              # competence need frustration
    paste0("auto", 1:4),              # autonomy need frustration
    paste0("relt", 1:4),              # relatedness need frustration
    "atcb2", "atcb5", "atcb6", "atcb7"  # turnover intentions
)

# L1 scale mean columns used for per-survey Mahalanobis
l1_scale_cols <- c(
    "pf_mean", "cw_mean", "ee_mean",
    "comp_mean", "auto_mean", "relt_mean",
    "atcb_mean", "turnover_intention_mean"
)

# L2 items: from intake survey, constant across surveys (20 items total)
l2_item_cols <- c(
    paste0("pa",  1:5),  # positive affect
    paste0("na",  1:5),  # negative affect
    paste0("br",  1:5),  # psychological contract breach
    paste0("vio", 1:4),  # contract violation
    "js1"                # job satisfaction (single item)
)

# L2 scale mean columns used for person-level Mahalanobis
l2_scale_cols <- c("pa_mean", "na_mean", "br_mean", "vio_mean", "js_mean")

missing_l1 <- setdiff(l1_item_cols,  names(df_raw))
missing_l2 <- setdiff(l2_item_cols,  names(df_raw))
missing_s1 <- setdiff(l1_scale_cols, names(df_raw))
missing_s2 <- setdiff(l2_scale_cols, names(df_raw))
if (length(c(missing_l1, missing_l2, missing_s1, missing_s2)) > 0) {
    stop("Missing columns: ", paste(c(missing_l1, missing_l2, missing_s1, missing_s2), collapse = ", "))
}
log_msg("L1 item block: ", length(l1_item_cols), " items | scale means: ", length(l1_scale_cols))
log_msg("L2 item block: ", length(l2_item_cols), " items | scale means: ", length(l2_scale_cols))


# =============================================================================
# [3] PER-SURVEY L1 CARELESS INDICES (longstring, IRV, duration)
# =============================================================================
log_msg("=== [3] Per-survey L1 indices (longstring, IRV, duration) ===")

#' Compute longstring, IRV, and duration for one survey slice
#'
#' @param df_survey Data frame rows for a single timepoint.
#' @param item_cols Character vector of L1 item column names.
#' @return Tibble: response_id, timepoint, survey_label, longstring, irv, duration.
compute_l1_survey_indices <- function(df_survey, item_cols) {
    mat <- as.matrix(df_survey[, item_cols])
    tibble::tibble(
        response_id   = df_survey$response_id,
        timepoint     = df_survey$timepoint,
        survey_label  = survey_label(df_survey$timepoint),
        duration      = df_survey$duration,
        longstring_l1 = careless::longstring(mat),
        irv_l1        = careless::irv(mat)
    )
}

l1_survey_indices <- df_raw |>
    dplyr::group_by(timepoint) |>
    dplyr::group_split() |>
    lapply(compute_l1_survey_indices, item_cols = l1_item_cols) |>
    dplyr::bind_rows() |>
    dplyr::mutate(
        survey_label  = factor(survey_label, levels = paste0("Survey ", sort(unique(timepoint)))),
        flag_ls_l1    = longstring_l1 > THRESH_LONGSTRING_L1,
        flag_irv_l1   = irv_l1        < THRESH_IRV_L1,
        flag_duration = duration       < THRESH_DURATION_SECS
    )

log_msg(
    "L1 indices computed: ",
    nrow(l1_survey_indices), " observations across ",
    dplyr::n_distinct(l1_survey_indices$timepoint), " surveys"
)


# =============================================================================
# [4] PER-SURVEY L1 MAHALANOBIS (on scale means at each survey)
# =============================================================================
log_msg("=== [4] Per-survey Mahalanobis L1 (scale means per survey) ===")

mahad_l1_cutoff <- qchisq(THRESH_MAHAD_CONF, df = length(l1_scale_cols))
log_msg(
    "L1 Mahalanobis cutoff: ", round(mahad_l1_cutoff, 2),
    " (chi-sq df=", length(l1_scale_cols), ", p=", THRESH_MAHAD_CONF, ")"
)

#' Compute Mahalanobis distance on L1 scale means for one survey slice
#'
#' @param df_survey Data frame rows for a single timepoint.
#' @param scale_cols Character vector of L1 scale mean column names.
#' @param cutoff Numeric; chi-squared cutoff for flagging.
#' @return Tibble: response_id, timepoint, mahad_l1_dist, flag_mahad_l1.
compute_l1_mahad <- function(df_survey, scale_cols, cutoff) {
    mat <- as.matrix(df_survey[, scale_cols])
    tibble::tibble(
        response_id   = df_survey$response_id,
        timepoint     = df_survey$timepoint,
        survey_label  = survey_label(df_survey$timepoint),
        mahad_l1_dist = careless::mahad(mat),
        flag_mahad_l1 = mahad_l1_dist > cutoff
    )
}

l1_mahad <- df_raw |>
    dplyr::group_by(timepoint) |>
    dplyr::group_split() |>
    lapply(compute_l1_mahad, scale_cols = l1_scale_cols, cutoff = mahad_l1_cutoff) |>
    dplyr::bind_rows() |>
    dplyr::mutate(
        survey_label = factor(survey_label, levels = paste0("Survey ", sort(unique(timepoint))))
    )

for (tp in sort(unique(l1_mahad$timepoint))) {
    n_flag <- sum(l1_mahad$flag_mahad_l1[l1_mahad$timepoint == tp])
    log_msg("  Survey ", tp, " flagged: ", n_flag)
}


# =============================================================================
# [5] L2 CARELESS INDICES (longstring, IRV, Mahalanobis — once per person)
# =============================================================================
log_msg("=== [5] L2 indices (intake block — once per person) ===")

df_l2 <- df_raw |>
    dplyr::distinct(response_id, .keep_all = TRUE)

# Longstring and IRV on L2 items
l2_item_mat <- as.matrix(df_l2[, l2_item_cols])
l2_scale_mat <- as.matrix(df_l2[, l2_scale_cols])

mahad_l2_cutoff <- qchisq(THRESH_MAHAD_CONF, df = length(l2_scale_cols))
log_msg(
    "L2 Mahalanobis cutoff: ", round(mahad_l2_cutoff, 2),
    " (chi-sq df=", length(l2_scale_cols), ", p=", THRESH_MAHAD_CONF, ")"
)

l2_indices <- tibble::tibble(
    response_id   = df_l2$response_id,
    longstring_l2 = careless::longstring(l2_item_mat),
    irv_l2        = careless::irv(l2_item_mat),
    mahad_l2_dist = careless::mahad(l2_scale_mat),
    flag_ls_l2    = longstring_l2 > THRESH_LONGSTRING_L2,
    flag_irv_l2   = irv_l2        < THRESH_IRV_L2,
    flag_mahad_l2 = mahad_l2_dist > mahad_l2_cutoff
)

log_msg("L2 longstring flagged: ", sum(l2_indices$flag_ls_l2))
log_msg("L2 IRV flagged:        ", sum(l2_indices$flag_irv_l2))
log_msg("L2 Mahalanobis flagged: ", sum(l2_indices$flag_mahad_l2))


# =============================================================================
# [6] PER-SURVEY DETAIL TABLE AND PERSON-LEVEL AGGREGATION
# =============================================================================
log_msg("=== [6] Building per-survey detail and person-level summary ===")

# --- Per-survey detail (person x survey) -------------------------------------
survey_detail <- l1_survey_indices |>
    dplyr::left_join(
        l1_mahad |> dplyr::select(response_id, timepoint, mahad_l1_dist, flag_mahad_l1),
        by = c("response_id", "timepoint")
    ) |>
    dplyr::mutate(
        n_survey_flags = rowSums(
            dplyr::pick(flag_ls_l1, flag_irv_l1, flag_duration, flag_mahad_l1),
            na.rm = TRUE
        )
    ) |>
    dplyr::arrange(response_id, timepoint)

# --- Person-level aggregation ------------------------------------------------
# A criterion is TRUE at the person level if it triggered on ANY survey.
# This preserves sensitivity to survey-specific careless responding.
person_summary <- survey_detail |>
    dplyr::group_by(response_id) |>
    dplyr::summarise(
        # Worst-case raw values across surveys (for interpretability)
        longstring_l1_max = max(longstring_l1),
        irv_l1_min        = min(irv_l1),
        duration_min_secs = min(duration),
        mahad_l1_max      = max(mahad_l1_dist),
        # Per-survey raw values (wide: one column per timepoint)
        dplyr::across(
            longstring_l1,
            list(tp1 = ~ .x[timepoint == 1], tp2 = ~ .x[timepoint == 2], tp3 = ~ .x[timepoint == 3]),
            .names = "longstring_l1_{.fn}"
        ),
        dplyr::across(
            irv_l1,
            list(tp1 = ~ .x[timepoint == 1], tp2 = ~ .x[timepoint == 2], tp3 = ~ .x[timepoint == 3]),
            .names = "irv_l1_{.fn}"
        ),
        dplyr::across(
            duration,
            list(tp1 = ~ .x[timepoint == 1], tp2 = ~ .x[timepoint == 2], tp3 = ~ .x[timepoint == 3]),
            .names = "duration_{.fn}"
        ),
        dplyr::across(
            mahad_l1_dist,
            list(tp1 = ~ .x[timepoint == 1], tp2 = ~ .x[timepoint == 2], tp3 = ~ .x[timepoint == 3]),
            .names = "mahad_l1_{.fn}"
        ),
        # Person-level criterion flags (TRUE if ANY survey triggered)
        flag_longstring_l1 = any(flag_ls_l1),
        flag_irv_l1        = any(flag_irv_l1),
        flag_duration      = any(flag_duration),
        flag_mahad_l1      = any(flag_mahad_l1),
        .groups = "drop"
    ) |>
    dplyr::left_join(l2_indices, by = "response_id") |>
    dplyr::mutate(
        # Combined Mahalanobis flag: L1 (any survey) or L2
        flag_mahad = flag_mahad_l1 | flag_mahad_l2,
        # Person-level criterion count (6 criteria; use actual post-join column names)
        n_flags = rowSums(
            dplyr::pick(flag_longstring_l1, flag_ls_l2, flag_irv_l1, flag_irv_l2, flag_duration, flag_mahad),
            na.rm = TRUE
        ),
        exclude = n_flags >= MIN_FLAGS_TO_EXCLUDE
    )

n_excluded <- sum(person_summary$exclude)
n_retained <- n_participants - n_excluded

log_msg("Participants with >= 1 flag: ", sum(person_summary$n_flags >= 1L))
log_msg("Participants excluded (>= ", MIN_FLAGS_TO_EXCLUDE, " criteria): ", n_excluded)
log_msg("Participants retained: ", n_retained)

# Per-criterion counts at person level
crit_person <- c(
    "Longstring L1 (any survey)" = sum(person_summary$flag_longstring_l1),
    "Longstring L2 (intake)"     = sum(person_summary$flag_ls_l2),
    "IRV L1 (any survey)"        = sum(person_summary$flag_irv_l1),
    "IRV L2 (intake)"            = sum(person_summary$flag_irv_l2),
    "Duration (any survey)"      = sum(person_summary$flag_duration),
    "Mahalanobis (L1+L2)"        = sum(person_summary$flag_mahad)
)
log_msg("Per-criterion person-level flag counts:")
for (nm in names(crit_person)) log_msg("  ", nm, ": ", crit_person[[nm]])

# Per-criterion, per-survey counts for figures
survey_flag_counts <- survey_detail |>
    dplyr::group_by(survey_label, timepoint) |>
    dplyr::summarise(
        "Longstring L1" = sum(flag_ls_l1),
        "IRV L1"        = sum(flag_irv_l1),
        "Duration"      = sum(flag_duration),
        "Mahalanobis L1" = sum(flag_mahad_l1),
        .groups = "drop"
    ) |>
    tidyr::pivot_longer(
        -c(survey_label, timepoint),
        names_to = "criterion", values_to = "n_flagged"
    )


# =============================================================================
# [7] DIAGNOSTIC FIGURES
# =============================================================================
log_msg("=== [7] Generating diagnostic figures ===")

# Shared color palette
col_retained <- "#2c7bb6"
col_flagged  <- "#d7191c"
col_threshold <- "#d7191c"

# --- [7a] L1 Longstring — faceted by survey ----------------------------------
flag_counts_ls <- l1_survey_indices |>
    dplyr::group_by(survey_label) |>
    dplyr::summarise(n_flagged = sum(flag_ls_l1), .groups = "drop")

p_ls_l1 <- ggplot(l1_survey_indices, aes(x = longstring_l1)) +
    geom_histogram(binwidth = 1, fill = col_retained, color = "white", alpha = 0.85) +
    geom_vline(xintercept = THRESH_LONGSTRING_L1 + 0.5,
               color = col_threshold, linetype = "dashed", linewidth = 0.8) +
    geom_text(
        data = flag_counts_ls,
        aes(x = Inf, y = Inf, label = paste0("Flagged: ", n_flagged)),
        hjust = 1.1, vjust = 1.4, size = 3.2, inherit.aes = FALSE
    ) +
    facet_wrap(~ survey_label, ncol = 3) +
    facet_theme +
    labs(
        title    = "L1 Longstring — consecutive identical responses per survey",
        subtitle = paste0("Flag threshold: > ", THRESH_LONGSTRING_L1, " of 30 items"),
        x        = "Max consecutive identical responses",
        y        = "Count"
    )

save_fig(p_ls_l1, "dq_01_longstring_l1_by_survey.svg", width = 12, height = 5)

# --- [7b] L1 IRV — faceted by survey -----------------------------------------
flag_counts_irv <- l1_survey_indices |>
    dplyr::group_by(survey_label) |>
    dplyr::summarise(n_flagged = sum(flag_irv_l1), .groups = "drop")

p_irv_l1 <- ggplot(l1_survey_indices, aes(x = irv_l1)) +
    geom_histogram(bins = 30, fill = col_retained, color = "white", alpha = 0.85) +
    geom_vline(xintercept = THRESH_IRV_L1,
               color = col_threshold, linetype = "dashed", linewidth = 0.8) +
    geom_text(
        data = flag_counts_irv,
        aes(x = -Inf, y = Inf, label = paste0("Flagged: ", n_flagged)),
        hjust = -0.1, vjust = 1.4, size = 3.2, inherit.aes = FALSE
    ) +
    facet_wrap(~ survey_label, ncol = 3) +
    facet_theme +
    labs(
        title    = "L1 IRV — intra-individual response variability per survey",
        subtitle = paste0("Flag threshold: < ", THRESH_IRV_L1, " SD"),
        x        = "Response variability (SD)",
        y        = "Count"
    )

save_fig(p_irv_l1, "dq_02_irv_l1_by_survey.svg", width = 12, height = 5)

# --- [7c] Duration — faceted by survey ---------------------------------------
flag_counts_dur <- l1_survey_indices |>
    dplyr::group_by(survey_label) |>
    dplyr::summarise(n_flagged = sum(flag_duration), .groups = "drop")

p_dur <- ggplot(l1_survey_indices, aes(x = duration)) +
    geom_histogram(bins = 40, fill = col_retained, color = "white", alpha = 0.85) +
    geom_vline(xintercept = THRESH_DURATION_SECS,
               color = col_threshold, linetype = "dashed", linewidth = 0.8) +
    geom_text(
        data = flag_counts_dur,
        aes(x = Inf, y = Inf, label = paste0("Flagged: ", n_flagged)),
        hjust = 1.1, vjust = 1.4, size = 3.2, inherit.aes = FALSE
    ) +
    facet_wrap(~ survey_label, ncol = 3) +
    facet_theme +
    labs(
        title    = "Survey duration per survey",
        subtitle = paste0("Flag threshold: < ", THRESH_DURATION_SECS, " seconds"),
        x        = "Duration (seconds)",
        y        = "Count"
    )

save_fig(p_dur, "dq_03_duration_by_survey.svg", width = 12, height = 5)

# --- [7d] L1 Mahalanobis — faceted by survey ----------------------------------
mahad_l1_ranked <- l1_mahad |>
    dplyr::group_by(timepoint) |>
    dplyr::arrange(mahad_l1_dist) |>
    dplyr::mutate(rank = seq_len(dplyr::n())) |>
    dplyr::ungroup()

flag_counts_mh <- l1_mahad |>
    dplyr::group_by(survey_label) |>
    dplyr::summarise(n_flagged = sum(flag_mahad_l1), .groups = "drop")

p_mahad_l1 <- ggplot(mahad_l1_ranked, aes(x = rank, y = mahad_l1_dist, color = flag_mahad_l1)) +
    geom_point(alpha = 0.55, size = 1.0) +
    geom_hline(yintercept = mahad_l1_cutoff,
               color = col_threshold, linetype = "dashed", linewidth = 0.8) +
    geom_text(
        data = flag_counts_mh,
        aes(x = Inf, y = Inf, label = paste0("Flagged: ", n_flagged)),
        hjust = 1.1, vjust = 1.4, size = 3.2, color = "black", inherit.aes = FALSE
    ) +
    scale_color_manual(
        values = c("FALSE" = col_retained, "TRUE" = col_flagged),
        labels = c("Retained", "Flagged"),
        name   = NULL
    ) +
    facet_wrap(~ survey_label, ncol = 3) +
    facet_theme +
    labs(
        title    = "L1 Mahalanobis distance — multivariate outliers per survey",
        subtitle = paste0(
            "Cutoff: ", round(mahad_l1_cutoff, 1),
            " (chi-sq df=", length(l1_scale_cols), ", p=", THRESH_MAHAD_CONF, ")"
        ),
        x = "Participant rank (within survey)",
        y = "Mahalanobis distance"
    ) +
    theme(legend.position = "bottom")

save_fig(p_mahad_l1, "dq_04_mahalanobis_l1_by_survey.svg", width = 12, height = 5)

# --- [7e] L2 intake indices (single-panel; no faceting) ----------------------
p_ls_l2 <- ggplot(l2_indices, aes(x = longstring_l2)) +
    geom_histogram(binwidth = 1, fill = "#1a9641", color = "white", alpha = 0.85) +
    geom_vline(xintercept = THRESH_LONGSTRING_L2 + 0.5,
               color = col_threshold, linetype = "dashed", linewidth = 0.8) +
    labs(
        title    = "L2 Longstring (intake block)",
        subtitle = paste0("Threshold: > ", THRESH_LONGSTRING_L2, " | Flagged: ", sum(l2_indices$flag_ls_l2)),
        x        = "Max consecutive identical responses",
        y        = "Count"
    )

p_irv_l2 <- ggplot(l2_indices, aes(x = irv_l2)) +
    geom_histogram(bins = 30, fill = "#1a9641", color = "white", alpha = 0.85) +
    geom_vline(xintercept = THRESH_IRV_L2,
               color = col_threshold, linetype = "dashed", linewidth = 0.8) +
    labs(
        title    = "L2 IRV (intake block)",
        subtitle = paste0("Threshold: < ", THRESH_IRV_L2, " | Flagged: ", sum(l2_indices$flag_irv_l2)),
        x        = "Response variability (SD)",
        y        = "Count"
    )

mahad_l2_ranked <- l2_indices |>
    dplyr::arrange(mahad_l2_dist) |>
    dplyr::mutate(rank = seq_len(dplyr::n()))

p_mahad_l2 <- ggplot(mahad_l2_ranked, aes(x = rank, y = mahad_l2_dist, color = flag_mahad_l2)) +
    geom_point(alpha = 0.55, size = 1.0) +
    geom_hline(yintercept = mahad_l2_cutoff,
               color = col_threshold, linetype = "dashed", linewidth = 0.8) +
    scale_color_manual(
        values = c("FALSE" = "#1a9641", "TRUE" = col_flagged),
        labels = c("Retained", "Flagged"),
        name   = NULL
    ) +
    labs(
        title    = "L2 Mahalanobis distance (intake scale means)",
        subtitle = paste0(
            "Cutoff: ", round(mahad_l2_cutoff, 1),
            " (chi-sq df=", length(l2_scale_cols), ", p=", THRESH_MAHAD_CONF, ")",
            " | Flagged: ", sum(l2_indices$flag_mahad_l2)
        ),
        x = "Participant rank",
        y = "Mahalanobis distance"
    ) +
    theme(legend.position = "bottom")

save_fig(
    (p_ls_l2 | p_irv_l2 | p_mahad_l2) +
        patchwork::plot_annotation(title = "Intake (L2) careless responding indices"),
    "dq_05_l2_indices.svg",
    width = 14, height = 5
)

# --- [7f] Flag summary — per-survey and person-level -------------------------
# Panel A: per-criterion flags broken down by survey (L1 criteria)
survey_order <- paste0("Survey ", sort(unique(l1_survey_indices$timepoint)))
pal_surveys  <- viridis::viridis(n_surveys, end = 0.85)
names(pal_surveys) <- survey_order

p_criteria_by_survey <- ggplot(
    survey_flag_counts |>
        dplyr::mutate(
            criterion    = factor(criterion,    levels = c("Longstring L1", "IRV L1", "Duration", "Mahalanobis L1")),
            survey_label = factor(survey_label, levels = survey_order)
        ),
    aes(x = criterion, y = n_flagged, fill = survey_label)
) +
    geom_col(position = "dodge", width = 0.65, alpha = 0.9) +
    geom_text(
        aes(label = n_flagged),
        position = position_dodge(width = 0.65),
        vjust = -0.4, size = 3.0
    ) +
    scale_fill_manual(values = pal_surveys, name = NULL) +
    labs(
        title    = "Flagged observations per L1 criterion by survey",
        subtitle = paste0("N observations per survey: ", nrow(df_raw) / n_surveys),
        x        = NULL,
        y        = "Observations flagged"
    ) +
    theme(legend.position = "bottom")

# Panel B: person-level flag count distribution
flag_dist <- person_summary |>
    dplyr::count(n_flags) |>
    dplyr::mutate(excluded = n_flags >= MIN_FLAGS_TO_EXCLUDE)

p_nflags <- ggplot(flag_dist, aes(x = factor(n_flags), y = n, fill = excluded)) +
    geom_col(width = 0.6, alpha = 0.88) +
    geom_text(aes(label = n), vjust = -0.4, size = 3.5) +
    scale_fill_manual(
        values = c("FALSE" = col_retained, "TRUE" = col_flagged),
        labels = c("Retained", "Excluded"),
        name   = NULL
    ) +
    labs(
        title    = "Person-level criteria flag count",
        subtitle = paste0(
            "N = ", n_participants,
            " | Excluded (>= ", MIN_FLAGS_TO_EXCLUDE, " criteria): ", n_excluded,
            " | Retained: ", n_retained
        ),
        x = "Number of person-level criteria flagged",
        y = "Participants"
    ) +
    theme(legend.position = "bottom")

save_fig(
    p_criteria_by_survey / p_nflags,
    "dq_06_flag_summary.svg",
    width = 12, height = 10
)

log_msg("Diagnostic figures saved to: ", FIGS_DIR)


# =============================================================================
# [8] SCREENING OUTPUT TABLES
# =============================================================================
log_msg("=== [8] Writing screening tables ===")

# --- Per-survey detail (person x survey) -----
detail_path <- file.path(FIGS_DIR, "dq_07_screening_detail.csv")
readr::write_csv(
    survey_detail |>
        dplyr::select(
            response_id, timepoint, survey_label,
            duration, longstring_l1, irv_l1, mahad_l1_dist,
            flag_ls_l1, flag_irv_l1, flag_duration, flag_mahad_l1,
            n_survey_flags
        ),
    detail_path
)
log_msg("Per-survey detail: ", detail_path)

# --- Person-level summary -----
# Rename flag columns for clarity before writing
person_out <- person_summary |>
    dplyr::rename(
        flag_longstring_l2 = flag_ls_l2,
        flag_irv_l2_col    = flag_irv_l2
    ) |>
    dplyr::select(
        response_id,
        # Worst-case aggregates
        longstring_l1_max, irv_l1_min, duration_min_secs, mahad_l1_max,
        # Per-survey raw values
        dplyr::starts_with("longstring_l1_tp"),
        dplyr::starts_with("irv_l1_tp"),
        dplyr::starts_with("duration_tp"),
        dplyr::starts_with("mahad_l1_tp"),
        # L2 values
        longstring_l2, irv_l2, mahad_l2_dist,
        # Person-level criterion flags
        flag_longstring_l1, flag_longstring_l2,
        flag_irv_l1, flag_irv_l2_col,
        flag_duration, flag_mahad_l1, flag_mahad_l2, flag_mahad,
        n_flags, exclude
    )

summary_path <- file.path(FIGS_DIR, "dq_08_person_summary.csv")
readr::write_csv(person_out, summary_path)
log_msg("Person-level summary: ", summary_path)

# --- Excluded participants -----
excluded_out <- person_summary |>
    dplyr::filter(exclude) |>
    dplyr::select(
        response_id, n_flags,
        flag_longstring_l1, flag_ls_l2,
        flag_irv_l1, flag_irv_l2,
        flag_duration, flag_mahad,
        longstring_l1_max, irv_l1_min, duration_min_secs
    )

excluded_path <- file.path(FIGS_DIR, "dq_09_excluded_participants.csv")
readr::write_csv(excluded_out, excluded_path)
log_msg("Excluded participants (", nrow(excluded_out), "): ", excluded_path)


# =============================================================================
# [9] EXPORT CLEANED DATA
# =============================================================================
log_msg("=== [9] Writing cleaned dataset ===")

retained_ids <- person_summary |>
    dplyr::filter(!exclude) |>
    dplyr::pull(response_id)

df_cleaned <- df_raw |>
    dplyr::filter(response_id %in% retained_ids)

cleaned_path <- file.path(
    EXPORT_DIR,
    paste0("syn_qualtrics_fct_panel_responses_cleaned_", today, ".csv")
)
readr::write_csv(df_cleaned, cleaned_path)

log_msg("Cleaned dataset: ", basename(cleaned_path))
log_msg("  Original: ", nrow(df_raw), " rows, ", n_participants, " participants")
log_msg("  Cleaned:  ", nrow(df_cleaned), " rows, ", dplyr::n_distinct(df_cleaned$response_id), " participants")
log_msg("  Excluded: ", n_excluded, " participants (", round(n_excluded / n_participants * 100, 1), "%)")
log_msg("=== DATA QUALITY SCREENING COMPLETE ===")
