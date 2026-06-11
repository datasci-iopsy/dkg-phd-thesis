#!/usr/bin/env Rscript
# =============================================================================
# analysis/run_study_analysis/scripts/R/data_quality.R
#
# Careless responding detection and data quality screening for the real
# study panel dataset using the careless package (Yentes & Wilhelm, 2018).
#
# Repeated-measures design: 3 within-day followup surveys per participant.
# L1 indices are computed per survey independently. L2 (intake) indices are
# computed once per participant.
#
# EXCLUSION criteria (3; Meade & Craig 2012):
#   1. Instructed-response / attention checks -- applied upstream in SQL
#      (listwise deletion); all participants in this file have passed.
#   2. LongString L1/L2 -- max run of identical responses.
#   3. Mahalanobis distance L1/L2 -- multivariate outlier.
#
# DIAGNOSTIC criteria (3 additional; computed but do NOT trigger exclusion):
#   4. IRV L1    -- intra-individual response variability per survey.
#   5. IRV L2    -- intra-individual response variability on intake block.
#   6. Duration  -- survey completion time.
#
# Exclusion rule: participant flagged by >= 2 exclusion criteria.
# Since attention checks are already resolved, this means flagged by BOTH
# LongString AND Mahalanobis.
#
# Input:  data/export/qualtrics_fct_panel_responses.csv
# Output: data/export/qualtrics_fct_panel_responses_cleaned.csv (.rds)
#         figs/data_quality/ -- diagnostic SVGs + screening CSVs
#
# References:
#   Yentes & Wilhelm (2018). The careless R package.
#     Practical Assessment, Research & Evaluation, 23(2).
#   Meade & Craig (2012). Identifying careless responses in survey data.
#     Psychological Methods, 17(3), 437-455.
# =============================================================================

# --- [0] Libraries and setup -------------------------------------------------
library(careless)
library(ggplot2)
library(patchwork)
library(dplyr)
library(tidyr)
library(readr)
library(tibble)
library(here)

options(tibble.width = Inf)

source(here::here("analysis", "shared", "utils", "common_utils.r"))
source(here::here("analysis", "shared", "utils", "plot_utils.r"))

FIGS_DIR   <- here::here("analysis", "run_study_analysis", "figs", "data_quality")
EXPORT_DIR <- here::here("analysis", "run_study_analysis", "data", "export")
ensure_dir(FIGS_DIR)

theme_set(theme_apa)

save_fig <- make_save_fig(FIGS_DIR, default_height = 6)

survey_label <- function(tp) paste0("Survey ", tp)

facet_theme <- theme(
    strip.text       = element_text(face = "bold", size = 10),
    strip.background = element_rect(fill = "#f0f0f0", color = NA)
)

# ---------------------------------------------------------------------------
# Screening thresholds
# ---------------------------------------------------------------------------
THRESH_LONGSTRING_L1 <- 10L   # flag if > 10 of 31 L1 items identical in a run
THRESH_LONGSTRING_L2 <- 10L   # flag if > 10 of 23 L2 items identical in a run
THRESH_IRV_L1        <- 0.50  # diagnostic only; flag if SD < 0.50
THRESH_IRV_L2        <- 0.25  # diagnostic only; flag if SD < 0.25
THRESH_DURATION_SECS <- 90L   # diagnostic only; flag if duration < 90 seconds
THRESH_MAHAD_CONF    <- 0.999 # chi-squared confidence for Mahalanobis cutoff
# Exclude if both LongString AND Mahalanobis flagged (attention checks already resolved in SQL)
MIN_FLAGS_TO_EXCLUDE <- 2L

log_msg("=== DATA QUALITY SCREENING ===")
log_msg("Output directory: ", FIGS_DIR)
log_msg("Exclusion criteria (>= ", MIN_FLAGS_TO_EXCLUDE, " to exclude):")
log_msg("  [excl] Longstring L1 > ", THRESH_LONGSTRING_L1, " (of 31 items per survey)")
log_msg("  [excl] Longstring L2 > ", THRESH_LONGSTRING_L2, " (of 23 items, intake block)")
log_msg("  [excl] Mahalanobis (chi-sq p=", THRESH_MAHAD_CONF, ")")
log_msg("Diagnostic criteria (computed, not used for exclusion):")
log_msg("  [diag] IRV L1 < ", THRESH_IRV_L1)
log_msg("  [diag] IRV L2 < ", THRESH_IRV_L2)
log_msg("  [diag] Duration < ", THRESH_DURATION_SECS, " seconds")


# =============================================================================
# [1] DATA LOADING
# =============================================================================
log_msg("=== [1] Loading data ===")

input_path <- file.path(EXPORT_DIR, "qualtrics_fct_panel_responses.csv")
if (!file.exists(input_path)) {
    stop(
        "No panel CSV found. Expected: ",
        input_path,
        "\nRun export_study_fct_panel_responses_csv.sh first."
    )
}
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

# L1 items: followup surveys (31 items -- 30 scored + TI single item)
l1_item_cols <- c(
    paste0("pf",   1:6),                       # physical fatigue (6)
    paste0("cw",   1:5),                       # cognitive weariness (5)
    paste0("ee",   1:3),                       # emotional exhaustion (3)
    paste0("comp", 1:4),                       # competence NF (4)
    paste0("auto", 1:4),                       # autonomy NF (4)
    paste0("relt", 1:4),                       # relatedness NF (4)
    "atcb2", "atcb5", "atcb6", "atcb7",        # ATCB marker (4)
    "turnover_intention"                        # TI single item (1)
)

# L1 scale means used for per-survey Mahalanobis
l1_scale_cols <- c(
    "pf_mean", "cw_mean", "ee_mean",
    "comp_mean", "auto_mean", "relt_mean",
    "atcb_mean", "turnover_intention_mean"
)

# L2 items: intake survey (23 items)
l2_item_cols <- c(
    paste0("pa",  1:5),  # positive affect (5)
    paste0("na",  1:5),  # negative affect (5)
    paste0("br",  1:5),  # psychological contract breach (5)
    paste0("vio", 1:4),  # contract violation (4)
    "js1",               # job satisfaction (1)
    "jis1",              # job insecurity (1)
    "des1", "des2"       # desirability of movement (2)
)

# L2 scale means used for person-level Mahalanobis
l2_scale_cols <- c("pa_mean", "na_mean", "br_mean", "vio_mean", "js_mean",
                   "jis_mean", "des_mean")

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
#'
compute_l1_survey_indices <- function(df_survey, item_cols) {
    mat <- as.matrix(df_survey[, item_cols])
    tibble::tibble(
        response_id   = df_survey$response_id,
        timepoint     = df_survey$timepoint,
        survey_label  = survey_label(df_survey$timepoint[[1]]),
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
    "L1 indices: ", nrow(l1_survey_indices), " obs across ",
    dplyr::n_distinct(l1_survey_indices$timepoint), " surveys"
)


# =============================================================================
# [4] PER-SURVEY L1 MAHALANOBIS
# =============================================================================
log_msg("=== [4] Per-survey Mahalanobis L1 ===")

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
#' @return Tibble: response_id, timepoint, survey_label, mahad_l1_dist, flag_mahad_l1.
#'
compute_l1_mahad <- function(df_survey, scale_cols, cutoff) {
    mat <- as.matrix(df_survey[, scale_cols])
    tibble::tibble(
        response_id   = df_survey$response_id,
        timepoint     = df_survey$timepoint,
        survey_label  = survey_label(df_survey$timepoint[[1]]),
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
# [5] L2 CARELESS INDICES (intake block -- once per person)
# =============================================================================
log_msg("=== [5] L2 indices (intake block) ===")

df_l2 <- df_raw |>
    dplyr::distinct(response_id, .keep_all = TRUE)

l2_item_mat  <- as.matrix(df_l2[, l2_item_cols])
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

log_msg("L2 longstring flagged:    ", sum(l2_indices$flag_ls_l2), " [excl]")
log_msg("L2 IRV flagged:           ", sum(l2_indices$flag_irv_l2), " [diag]")
log_msg("L2 Mahalanobis flagged:   ", sum(l2_indices$flag_mahad_l2), " [excl]")


# =============================================================================
# [6] PER-SURVEY DETAIL AND PERSON-LEVEL AGGREGATION
# =============================================================================
log_msg("=== [6] Person-level aggregation ===")

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

person_summary <- survey_detail |>
    dplyr::group_by(response_id) |>
    dplyr::summarise(
        longstring_l1_max = max(longstring_l1),
        irv_l1_min        = min(irv_l1),
        duration_min_secs = min(duration),
        mahad_l1_max      = max(mahad_l1_dist),
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
        # Combined exclusion flags (Meade & Craig 2012 indicators 2 and 3)
        flag_longstring = flag_longstring_l1 | flag_ls_l2,
        flag_mahad      = flag_mahad_l1 | flag_mahad_l2,
        # Exclusion count: only 2 exclusion criteria (attention checks already applied)
        n_excl_flags = rowSums(
            dplyr::pick(flag_longstring, flag_mahad),
            na.rm = TRUE
        ),
        # Diagnostic flag count (all 4 non-exclusion indicators)
        n_diag_flags = rowSums(
            dplyr::pick(flag_irv_l1, flag_irv_l2, flag_duration),
            na.rm = TRUE
        ),
        exclude = n_excl_flags >= MIN_FLAGS_TO_EXCLUDE
    )

n_excluded <- sum(person_summary$exclude)
n_retained <- n_participants - n_excluded

log_msg("Participants with >= 1 exclusion flag: ", sum(person_summary$n_excl_flags >= 1L))
log_msg(
    "Participants excluded (>= ", MIN_FLAGS_TO_EXCLUDE,
    " exclusion criteria, i.e. both LongString AND Mahalanobis): ", n_excluded
)
log_msg("Participants retained: ", n_retained)

crit_counts <- c(
    "[excl] LongString (L1 or L2)" = sum(person_summary$flag_longstring),
    "[excl] Mahalanobis (L1 or L2)" = sum(person_summary$flag_mahad),
    "[diag] IRV L1 (any survey)"    = sum(person_summary$flag_irv_l1),
    "[diag] IRV L2 (intake)"        = sum(l2_indices$flag_irv_l2),
    "[diag] Duration (any survey)"  = sum(person_summary$flag_duration)
)
log_msg("Per-criterion person-level counts:")
for (nm in names(crit_counts)) log_msg("  ", nm, ": ", crit_counts[[nm]])

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

col_retained  <- "#2c7bb6"
col_flagged   <- "#d7191c"
col_threshold <- "#d7191c"
col_l2        <- "#1a9641"

# [7a] L1 Longstring by survey
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
        title    = "L1 LongString [excl] -- consecutive identical responses per survey",
        subtitle = paste0("Flag threshold: > ", THRESH_LONGSTRING_L1, " of ", length(l1_item_cols), " items"),
        x        = "Max consecutive identical responses",
        y        = "Count"
    )
save_fig(p_ls_l1, "dq_01_longstring_l1_by_survey.svg", width = 12, height = 5)

# [7b] L1 IRV by survey
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
        title    = "L1 IRV [diag] -- intra-individual response variability per survey",
        subtitle = paste0("Diagnostic threshold: < ", THRESH_IRV_L1, " SD (not used for exclusion)"),
        x        = "Response variability (SD)",
        y        = "Count"
    )
save_fig(p_irv_l1, "dq_02_irv_l1_by_survey.svg", width = 12, height = 5)

# [7c] Duration by survey
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
        title    = "Duration [diag] -- survey completion time",
        subtitle = paste0("Diagnostic threshold: < ", THRESH_DURATION_SECS, " seconds (not used for exclusion)"),
        x        = "Duration (seconds)",
        y        = "Count"
    )
save_fig(p_dur, "dq_03_duration_by_survey.svg", width = 12, height = 5)

# [7d] L1 Mahalanobis by survey
mahad_l1_ranked <- l1_mahad |>
    dplyr::group_by(timepoint) |>
    dplyr::arrange(mahad_l1_dist) |>
    dplyr::mutate(rank = seq_len(dplyr::n())) |>
    dplyr::ungroup()

flag_counts_mh <- l1_mahad |>
    dplyr::group_by(survey_label) |>
    dplyr::summarise(n_flagged = sum(flag_mahad_l1), .groups = "drop")

p_mahad_l1 <- ggplot(
    mahad_l1_ranked,
    aes(x = rank, y = mahad_l1_dist, color = flag_mahad_l1)
) +
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
        title    = "L1 Mahalanobis [excl] -- multivariate outliers per survey",
        subtitle = paste0(
            "Cutoff: ", round(mahad_l1_cutoff, 1),
            " (chi-sq df=", length(l1_scale_cols), ", p=", THRESH_MAHAD_CONF, ")"
        ),
        x = "Participant rank (within survey)",
        y = "Mahalanobis distance"
    ) +
    theme(legend.position = "bottom")
save_fig(p_mahad_l1, "dq_04_mahalanobis_l1_by_survey.svg", width = 12, height = 5)

# [7e] L2 intake indices
p_ls_l2 <- ggplot(l2_indices, aes(x = longstring_l2)) +
    geom_histogram(binwidth = 1, fill = col_l2, color = "white", alpha = 0.85) +
    geom_vline(xintercept = THRESH_LONGSTRING_L2 + 0.5,
               color = col_threshold, linetype = "dashed", linewidth = 0.8) +
    labs(
        title    = "L2 LongString [excl] (intake)",
        subtitle = paste0("Threshold > ", THRESH_LONGSTRING_L2, " | Flagged: ", sum(l2_indices$flag_ls_l2)),
        x        = "Max consecutive identical responses",
        y        = "Count"
    )

p_irv_l2 <- ggplot(l2_indices, aes(x = irv_l2)) +
    geom_histogram(bins = 30, fill = col_l2, color = "white", alpha = 0.85) +
    geom_vline(xintercept = THRESH_IRV_L2,
               color = col_threshold, linetype = "dashed", linewidth = 0.8) +
    labs(
        title    = "L2 IRV [diag] (intake)",
        subtitle = paste0("Threshold < ", THRESH_IRV_L2, " | Flagged: ", sum(l2_indices$flag_irv_l2)),
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
        values = c("FALSE" = col_l2, "TRUE" = col_flagged),
        labels = c("Retained", "Flagged"),
        name   = NULL
    ) +
    labs(
        title    = "L2 Mahalanobis [excl] (intake scale means)",
        subtitle = paste0(
            "Cutoff: ", round(mahad_l2_cutoff, 1),
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

# [7f] Flag summary
survey_order <- paste0("Survey ", sort(unique(l1_survey_indices$timepoint)))
pal_surveys  <- viridis::viridis(n_surveys, end = 0.85)
names(pal_surveys) <- survey_order

p_criteria_by_survey <- ggplot(
    survey_flag_counts |>
        dplyr::mutate(
            criterion    = factor(criterion, levels = c("Longstring L1", "IRV L1", "Duration", "Mahalanobis L1")),
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
        title    = "Flagged observations per criterion by survey",
        subtitle = paste0(
            "N per survey: ", nrow(df_raw) / n_surveys,
            " | [excl] = exclusion criterion | [diag] = diagnostic only"
        ),
        x = NULL,
        y = "Observations flagged"
    ) +
    theme(legend.position = "bottom")

flag_dist <- person_summary |>
    dplyr::count(n_excl_flags) |>
    dplyr::mutate(excluded = n_excl_flags >= MIN_FLAGS_TO_EXCLUDE)

p_nflags <- ggplot(flag_dist, aes(x = factor(n_excl_flags), y = n, fill = excluded)) +
    geom_col(width = 0.6, alpha = 0.88) +
    geom_text(aes(label = n), vjust = -0.4, size = 3.5) +
    scale_fill_manual(
        values = c("FALSE" = col_retained, "TRUE" = col_flagged),
        labels = c("Retained", "Excluded"),
        name   = NULL
    ) +
    labs(
        title    = "Person-level exclusion criteria flag count",
        subtitle = paste0(
            "N=", n_participants,
            " | Excluded (both LongString AND Mahalanobis): ", n_excluded,
            " | Retained: ", n_retained
        ),
        x = "Exclusion criteria flagged (of 2: LongString, Mahalanobis)",
        y = "Participants"
    ) +
    theme(legend.position = "bottom")

save_fig(
    p_criteria_by_survey / p_nflags,
    "dq_06_flag_summary.svg",
    width = 12, height = 10
)

log_msg("Figures saved to: ", FIGS_DIR)


# =============================================================================
# [8] SCREENING OUTPUT TABLES
# =============================================================================
log_msg("=== [8] Writing screening tables ===")

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

summary_path <- file.path(FIGS_DIR, "dq_08_person_summary.csv")
readr::write_csv(
    person_summary |>
        dplyr::select(
            response_id,
            longstring_l1_max, irv_l1_min, duration_min_secs, mahad_l1_max,
            dplyr::starts_with("longstring_l1_tp"),
            dplyr::starts_with("irv_l1_tp"),
            dplyr::starts_with("duration_tp"),
            dplyr::starts_with("mahad_l1_tp"),
            longstring_l2, irv_l2, mahad_l2_dist,
            flag_longstring_l1, flag_ls_l2, flag_longstring,
            flag_irv_l1, flag_irv_l2,
            flag_duration,
            flag_mahad_l1, flag_mahad_l2, flag_mahad,
            n_excl_flags, n_diag_flags, exclude
        ),
    summary_path
)
log_msg("Person-level summary: ", summary_path)

excluded_path <- file.path(FIGS_DIR, "dq_09_excluded_participants.csv")
readr::write_csv(
    person_summary |>
        dplyr::filter(exclude) |>
        dplyr::select(
            response_id, n_excl_flags,
            flag_longstring, flag_mahad,
            longstring_l1_max, mahad_l1_max, mahad_l2_dist
        ),
    excluded_path
)
log_msg("Excluded participants (", sum(person_summary$exclude), "): ", excluded_path)


# =============================================================================
# [9] EXPORT CLEANED DATA
# =============================================================================
log_msg("=== [9] Writing cleaned dataset ===")

retained_ids <- person_summary |>
    dplyr::filter(!exclude) |>
    dplyr::pull(response_id)

df_cleaned <- df_raw |>
    dplyr::filter(response_id %in% retained_ids)

cleaned_path <- file.path(EXPORT_DIR, "qualtrics_fct_panel_responses_cleaned.csv")
readr::write_csv(df_cleaned, cleaned_path)
saveRDS(df_cleaned, file.path(EXPORT_DIR, "qualtrics_fct_panel_responses_cleaned.rds"))

log_msg("Cleaned dataset written: ", basename(cleaned_path))
log_msg("  Original:  ", nrow(df_raw), " rows, ", n_participants, " participants")
log_msg(
    "  Cleaned:   ", nrow(df_cleaned), " rows, ",
    dplyr::n_distinct(df_cleaned$response_id), " participants"
)
log_msg(
    "  Excluded:  ", n_excluded, " participants (",
    round(n_excluded / n_participants * 100, 1), "%)"
)
log_msg("=== DATA QUALITY SCREENING COMPLETE ===")
