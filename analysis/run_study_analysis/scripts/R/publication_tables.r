#!/usr/bin/env Rscript
# =============================================================================
# analysis/run_study_analysis/scripts/R/publication_tables.r
#
# Publication-ready Word tables for study analysis (NCSU ETD / APA 7th).
# Reads pre-computed CSVs from the analysis pipeline. Table 1 uses gtsummary
# directly on the cleaned participant-level CSV; Tables 2-5 use flextable/officer.
#
# Prerequisite: run make study_analysis (steps 1-5) first.
#
# Tables produced:
#   Table 1  -- Participant demographics and sample characteristics
#   Table 2  -- Descriptive statistics, reliabilities, and correlations
#   Table 3  -- Confirmatory factor analysis results (fit indices + loadings)
#   Table 4a -- Multilevel model results: M0-M6 (fixed effects + variance components)
#   Table 4b -- Moderation models: M7a/M7b (meeting count/time x burnout/NF)
#   Table 5  -- Hypothesis test summary
#
# Output: analysis/run_study_analysis/tables/*.docx (gitignored)
# =============================================================================

# --- [0] Libraries and setup --------------------------------------------------
library(gtsummary)
library(flextable)
library(officer)
library(dplyr)
library(tidyr)
library(readr)
library(purrr)
library(stringr)
library(tibble)
library(here)

options(tibble.width = Inf)

source(here::here("analysis", "shared", "utils", "common_utils.r"))
source(here::here("analysis", "shared", "utils", "table_utils.r"))

TABLES_DIR <- here::here("analysis", "run_study_analysis", "tables")
DATA_DIR <- here::here("analysis", "run_study_analysis", "data", "export")
EDA_DIR <- here::here("analysis", "run_study_analysis", "figs", "eda")
CORR_DIR <- here::here("analysis", "run_study_analysis", "figs", "corr")
CFA_DIR <- here::here("analysis", "run_study_analysis", "figs", "cfa")
MLM_DIR <- here::here("analysis", "run_study_analysis", "figs", "mlm")

ensure_dir(TABLES_DIR)

# Guard: all figs CSVs consumed by this script must be newer than the cleaned dataset.
# If any are stale, the table output would mix N values from different pipeline runs.
require_fresh(
    targets = c(
        file.path(EDA_DIR, "eda_04_descriptive_statistics.csv"),
        file.path(EDA_DIR, "eda_15_icc_table.csv"),
        file.path(CFA_DIR, "cfa_01_fit_indices.csv"),
        file.path(CFA_DIR, "cfa_02_loadings_l2.csv"),
        file.path(CFA_DIR, "cfa_03_loadings_l1.csv"),
        file.path(CFA_DIR, "cfa_04_omega.csv"),
        file.path(CFA_DIR, "cfa_05_marker_evidence.csv"),
        file.path(CFA_DIR, "cfa_06_marker_fit.csv"),
        file.path(CFA_DIR, "cfa_07_marker_lrt.csv"),
        file.path(CFA_DIR, "cfa_08_metric_invariance.csv"),
        file.path(CORR_DIR, "corr_01_l2_pearson_matrix.csv"),
        file.path(CORR_DIR, "corr_01_l2_pearson_pvalues.csv"),
        file.path(CORR_DIR, "corr_04_rmcorr_within_matrix.csv"),
        file.path(CORR_DIR, "corr_04_rmcorr_within_pvalues.csv"),
        file.path(CORR_DIR, "corr_05_between_person_matrix.csv"),
        file.path(CORR_DIR, "corr_05_between_person_pvalues.csv"),
        file.path(MLM_DIR, "mlm_01_model_comparison.csv"),
        file.path(MLM_DIR, "mlm_01b_phase6_comparison.csv"),
        file.path(MLM_DIR, "mlm_02_fixed_effects.csv"),
        file.path(MLM_DIR, "mlm_04_hypothesis_tests.csv"),
        file.path(MLM_DIR, "mlm_05_standardized_effects.csv"),
        file.path(MLM_DIR, "mlm_06_level_specific_es.csv"),
        file.path(MLM_DIR, "mlm_07_delta_r2.csv")
    ),
    prerequisites = file.path(DATA_DIR, "qualtrics_fct_panel_responses_cleaned.csv"),
    remediation = "make study_analysis"
)

log_msg("=== PUBLICATION TABLES (Study Analysis) ===")
log_msg("Output directory: ", TABLES_DIR)


# --- Canonical variable name mapping -----------------------------------------
var_labels <- c(
    pf_mean                  = "Physical Fatigue",
    cw_mean                  = "Cognitive Weariness",
    ee_mean                  = "Emotional Exhaustion",
    comp_mean                = "Competence Frustration",
    auto_mean                = "Autonomy Frustration",
    relt_mean                = "Relatedness Frustration",
    meetings_count           = "Meeting Count",
    meetings_time            = "Meeting Duration (min)",
    turnover_intention_mean  = "Turnover Intention",
    atcb_mean                = "Marker Variable (ATCB)",
    pa_mean                  = "Positive Affect",
    na_mean                  = "Negative Affect",
    br_mean                  = "PC Breach",
    vio_mean                 = "PC Violation",
    js_mean                  = "Job Satisfaction",
    jis_mean                 = "Job Insecurity",
    des_mean                 = "Desirability of Movement"
)

# Ordered row variables for Table 2 (conceptual grouping; excludes jis/des)
table2_vars <- c(
    "pf_mean", "cw_mean", "ee_mean",
    "comp_mean", "auto_mean", "relt_mean",
    "meetings_count", "meetings_time",
    "turnover_intention_mean",
    "atcb_mean",
    "pa_mean", "na_mean",
    "br_mean", "vio_mean",
    "js_mean"
)

# Single-item measures with no omega
no_omega_vars <- c(
    "meetings_count", "meetings_time",
    "turnover_intention_mean", "js_mean"
)

# L1 vs L2 classification
l1_vars <- c(
    "pf_mean", "cw_mean", "ee_mean",
    "comp_mean", "auto_mean", "relt_mean",
    "meetings_count", "meetings_time",
    "turnover_intention_mean", "atcb_mean"
)
l2_vars <- c("pa_mean", "na_mean", "br_mean", "vio_mean", "js_mean")

# CFA factor to variable mapping (for omega lookup)
factor_to_var <- c(
    PF      = "pf_mean",
    CW      = "cw_mean",
    EE      = "ee_mean",
    NF_COMP = "comp_mean",
    NF_AUTO = "auto_mean",
    NF_REL  = "relt_mean",
    ATCB    = "atcb_mean",
    POS_AFF = "pa_mean",
    NEG_AFF = "na_mean",
    PCB     = "br_mean",
    PCV     = "vio_mean"
)


# =============================================================================
# [1] TABLE 1: PARTICIPANT DEMOGRAPHICS  (gtsummary)
# =============================================================================
log_msg("=== [1] Table 1: Participant Demographics ===")

cleaned <- readr::read_csv(
    file.path(DATA_DIR, "qualtrics_fct_panel_responses_cleaned.csv"),
    show_col_types = FALSE
)

# L2 level: one row per participant
l2_demo <- cleaned |>
    dplyr::distinct(response_id, .keep_all = TRUE) |>
    dplyr::select(
        age, gender, ethnicity, edu_lvl, is_remote,
        job_tenure, recruitment_source
    ) |>
    dplyr::mutate(
        is_remote = dplyr::if_else(is_remote, "Yes", "No"),
        recruitment_source = dplyr::recode(recruitment_source,
            cloudresearch = "CloudResearch",
            snowball = "Snowball/Referral"
        ),
        # Order education levels sensibly
        edu_lvl = factor(edu_lvl, levels = c(
            "High school diploma or equivalent (e.g., GED)",
            "Some college, no degree",
            "Vocational training",
            "Associate degree",
            "Bachelor's degree",
            "Master's degree",
            "Professional or doctorate degree"
        ))
    )

n_participants <- nrow(l2_demo)

t1_gt <- gtsummary::tbl_summary(
    l2_demo,
    type = list(age ~ "continuous"),
    statistic = list(
        age ~ "{mean} ({sd})",
        all_categorical() ~ "{n} ({p}%)"
    ),
    digits = list(age ~ c(1, 1)),
    missing = "no",
    label = list(
        age                = "Age (years)",
        gender             = "Gender",
        ethnicity          = "Ethnicity",
        edu_lvl            = "Education Level",
        is_remote          = "Remote Work Status",
        job_tenure         = "Job Tenure",
        recruitment_source = "Recruitment Source"
    )
) |>
    gtsummary::modify_header(
        label  = "**Characteristic**",
        stat_0 = paste0("**N = ", n_participants, "**")
    )

ft1 <- gtsummary::as_flex_table(t1_gt) |>
    flextable::font(fontname = APA_FONT, part = "all") |>
    flextable::fontsize(size = APA_BODY_PT, part = "all") |>
    flextable::border_remove() |>
    flextable::hline_top(
        border = officer::fp_border(width = 1.5),
        part   = "header"
    ) |>
    flextable::hline_bottom(
        border = officer::fp_border(width = 0.75),
        part   = "header"
    ) |>
    flextable::hline_bottom(
        border = officer::fp_border(width = 1.5),
        part   = "body"
    ) |>
    flextable::padding(padding.top = 2, padding.bottom = 2, part = "all") |>
    flextable::autofit() |>
    flextable::fit_to_width(max_width = APA_PAGE_W) |>
    add_apa_note(paste0(
        "N = ", n_participants, " employees (3 observations per person). ",
        "Participants were recruited via two channels: CloudResearch (an online ",
        "crowdsourcing panel) and snowball/referral sampling through professional ",
        "networks. Proportions for each channel are shown under Recruitment Source. ",
        "M (SD) for continuous variables; n (%) for categorical variables."
    ))

save_docx_table(
    ft1,
    filepath  = file.path(TABLES_DIR, "table_01_demographics.docx"),
    table_num = 1,
    title     = "Participant Demographics and Sample Characteristics."
)


# =============================================================================
# [2] TABLE 2: DESCRIPTIVE STATISTICS, RELIABILITIES, AND CORRELATIONS
# =============================================================================
log_msg("=== [2] Table 2: Descriptives, Reliabilities, Correlations ===")

desc <- readr::read_csv(file.path(EDA_DIR, "eda_04_descriptive_statistics.csv"),
    show_col_types = FALSE
)
iccs <- readr::read_csv(file.path(EDA_DIR, "eda_15_icc_table.csv"),
    show_col_types = FALSE
)
omega <- readr::read_csv(file.path(CFA_DIR, "cfa_04_omega.csv"),
    show_col_types = FALSE
)

#' Read a correlation matrix CSV written by write.csv (row names in first column)
#'
#' @param path Character; path to the CSV file.
#' @return Named numeric matrix with row and column names restored.
read_matrix <- function(path) {
    m <- readr::read_csv(path, show_col_types = FALSE)
    rn <- m[[1]]
    m <- as.matrix(m[, -1])
    rownames(m) <- rn
    m
}

# Between-person: Pearson on person-level scores (corr_05; L1 vars averaged
# across timepoints + L2 intake vars). Within-person: rmcorr (corr_04).
# Table 2b uses corr_01 (L2 intake vars only; same person-level estimates).
bp_mat <- read_matrix(file.path(CORR_DIR, "corr_05_between_person_matrix.csv"))
bp_pmat <- read_matrix(file.path(CORR_DIR, "corr_05_between_person_pvalues.csv"))
wp_mat <- read_matrix(file.path(CORR_DIR, "corr_04_rmcorr_within_matrix.csv"))
wp_pmat <- read_matrix(file.path(CORR_DIR, "corr_04_rmcorr_within_pvalues.csv"))
l2_mat <- read_matrix(file.path(CORR_DIR, "corr_01_l2_pearson_matrix.csv"))
l2_pmat <- read_matrix(file.path(CORR_DIR, "corr_01_l2_pearson_pvalues.csv"))

#' Significance stars for a correlation p-value (APA convention)
#'
#' @param p Numeric p-value (scalar or vector); NA returns "".
#' @return Character string(s): "***", "**", "*", or "".
fmt_stars <- function(p) {
    dplyr::case_when(
        is.na(p) ~ "",
        p < .001 ~ "***",
        p < .01 ~ "**",
        p < .05 ~ "*",
        TRUE ~ ""
    )
}

# Omega lookup: within-level (L1) and between-level (L2)
omega_within <- omega |>
    dplyr::filter(level == "L1_within") |>
    dplyr::mutate(variable = factor_to_var[factor]) |>
    dplyr::filter(!is.na(variable)) |>
    dplyr::select(variable, omega)

omega_l2 <- omega |>
    dplyr::filter(level == "L2", type == "single_level") |>
    dplyr::mutate(variable = factor_to_var[factor]) |>
    dplyr::filter(!is.na(variable)) |>
    dplyr::select(variable, omega)

omega_all <- dplyr::bind_rows(omega_within, omega_l2)

# Descriptive stats and ICC lookups
# sprintf keeps trailing zeros (1.60, not 1.6) per APA decimal consistency
desc_lookup <- desc |>
    dplyr::select(variable, mean, sd) |>
    dplyr::mutate(dplyr::across(c(mean, sd), ~ sprintf("%.2f", .)))

icc_lookup <- iccs |>
    dplyr::select(variable, icc_adjusted) |>
    dplyr::mutate(icc_adjusted = round(icc_adjusted, 2))

n_obs <- max(desc$n[desc$level == "L1"], na.rm = TRUE)
n_prs <- max(desc$n[desc$level == "L2"], na.rm = TRUE)

# L1 vars for Table 2a (ATCB excluded; it is the CMV marker reported in CFA/Appendix B)
table2a_vars <- c(
    "pf_mean", "cw_mean", "ee_mean",
    "comp_mean", "auto_mean", "relt_mean",
    "meetings_count", "meetings_time",
    "turnover_intention_mean"
)
table2b_vars <- l2_vars

#' Look up a single cell from a named correlation matrix
#'
#' @param mat Numeric matrix with row and column names.
#' @param r   Character; row name.
#' @param c   Character; column name.
#' @return Numeric correlation value, or NA_real_ if absent.
get_corr <- function(mat, r, c) {
    if (r %in% rownames(mat) && c %in% colnames(mat)) mat[r, c] else NA_real_
}

#' Build a lower-triangle correlation cell matrix for a set of variables
#'
#' @param vars      Character vector of variable names (row/column order).
#' @param corr_mat  Named numeric matrix of correlation values.
#' @param omega_lkp Data frame with columns variable and omega.
#' @param no_omega  Character vector of variables that have no omega (single-item).
#' @param p_mat     Optional named numeric matrix of p-values; when supplied,
#'   correlations carry APA significance stars.
#' @param omega_diag Logical; TRUE puts omega in parens on the diagonal (for
#'   tables without an omega column), FALSE puts EMDASH (omega reported in a
#'   dedicated column instead).
#' @return Character matrix; diagonal = omega/EMDASH, lower = corr, upper = "".
build_corr_cells <- function(vars, corr_mat, omega_lkp, no_omega, p_mat = NULL,
                             omega_diag = TRUE) {
    n <- length(vars)
    cells <- matrix("", nrow = n, ncol = n, dimnames = list(vars, vars))
    for (i in seq_len(n)) {
        for (j in seq_len(n)) {
            ri <- vars[i]
            cj <- vars[j]
            if (i == j) {
                if (!omega_diag) {
                    cells[i, j] <- EMDASH
                    next
                }
                om <- omega_lkp$omega[omega_lkp$variable == ri]
                cells[i, j] <- if (length(om) > 0) {
                    paste0("(", fmt_r(om), ")")
                } else if (ri %in% no_omega) {
                    EMDASH
                } else {
                    ""
                }
            } else if (j < i) {
                r_val <- get_corr(corr_mat, ri, cj)
                if (!is.na(r_val)) {
                    star <- if (!is.null(p_mat)) fmt_stars(get_corr(p_mat, ri, cj)) else ""
                    cells[i, j] <- paste0(fmt_r(r_val), star)
                }
            }
        }
    }
    cells
}

# --- Table 2a: Within-Person (L1) Descriptives and Correlations ---------------
cells2a <- build_corr_cells(
    table2a_vars, wp_mat, omega_within, no_omega_vars, wp_pmat,
    omega_diag = FALSE
)

t2a_rows <- purrr::map_dfr(seq_along(table2a_vars), function(i) {
    v <- table2a_vars[i]
    d <- desc_lookup[desc_lookup$variable == v, ]
    icc_v <- icc_lookup$icc_adjusted[icc_lookup$variable == v]
    om_v <- omega_within$omega[omega_within$variable == v]
    row <- tibble::tibble(
        Variable = paste0(i, ". ", var_labels[v]),
        M = if (nrow(d) > 0) as.character(d$mean) else "",
        SD = if (nrow(d) > 0) as.character(d$sd) else "",
        ICC = if (length(icc_v) > 0) fmt_r(icc_v) else EMDASH,
        "ω" = if (length(om_v) > 0) fmt_r(om_v) else EMDASH
    )
    for (j in seq_along(table2a_vars)) row[[as.character(j)]] <- cells2a[i, j]
    row
})

note2a <- paste0(
    "N = ", n_prs, " participants; n = ", n_obs,
    " observations (3 timepoints per person). ",
    "Correlations are repeated-measures correlations (rmcorr; Bakdash & Marusich, 2017). ",
    "ω = McDonald's omega reliability coefficient (within-level from MCFA; Lai, 2021). ",
    "ICC = intraclass correlation from an unconditional means model. ",
    EMDASH, " = single-item measure or structurally inapplicable. ",
    "ATCB (common method marker variable) excluded; see Table 3 and Appendix B. ",
    "* p < .05. ** p < .01. *** p < .001."
)

# Explicit widths at 9pt: 14 columns at 12pt would trigger fit_to_width's
# font auto-shrink (~7.5pt); controlled 9pt with sized columns is more readable.
# Correlation columns need >= 0.42 in for starred values (e.g. ".64***").
# Total: 1.48 + 0.34 + 0.38 + 0.28 + 0.24 + 9*0.42 = 6.50 in
t2a_col_widths <- c(
    Variable = 1.48, M = 0.34, SD = 0.38, ICC = 0.28, "ω" = 0.24,
    setNames(rep(0.42, length(table2a_vars)), as.character(seq_along(table2a_vars)))
)
ft2a <- apa_flextable(t2a_rows, col_widths = t2a_col_widths) |>
    flextable::fontsize(size = 9, part = "all") |>
    flextable::padding(
        padding.top = 2.5, padding.bottom = 2.5,
        padding.left = 1.5, padding.right = 1.5,
        part = "all"
    ) |>
    add_apa_note(note2a)
save_docx_table(
    ft2a,
    filepath  = file.path(TABLES_DIR, "table_02a_l1_correlations.docx"),
    table_num = "2a",
    title     = "Within-Person Descriptive Statistics, Reliabilities, and Correlations."
)

# --- Table 2b: Between-Person (L2) Descriptives and Correlations --------------
cells2b <- build_corr_cells(
    table2b_vars, l2_mat, omega_l2, no_omega_vars, l2_pmat,
    omega_diag = FALSE
)

t2b_rows <- purrr::map_dfr(seq_along(table2b_vars), function(i) {
    v <- table2b_vars[i]
    d <- desc_lookup[desc_lookup$variable == v, ]
    om_v <- omega_l2$omega[omega_l2$variable == v]
    row <- tibble::tibble(
        ` ` = as.character(i),
        Variable = var_labels[v],
        M = if (nrow(d) > 0) as.character(d$mean) else "",
        SD = if (nrow(d) > 0) as.character(d$sd) else "",
        "ω" = if (length(om_v) > 0) fmt_r(om_v) else EMDASH
    )
    for (j in seq_along(table2b_vars)) row[[as.character(j)]] <- cells2b[i, j]
    row
})

note2b <- paste0(
    "N = ", n_prs, " participants. Correlations are Pearson r from person-mean scores. ",
    "ω = McDonald's omega reliability coefficient (single-level CFA, MLR estimation; ",
    "Lai, 2021). ", EMDASH, " = single-item measure (Job Satisfaction) or structurally ",
    "inapplicable. PC = Psychological Contract. ",
    "* p < .05. ** p < .01. *** p < .001."
)

ft2b <- apa_flextable(t2b_rows) |> add_apa_note(note2b)
save_docx_table(
    ft2b,
    filepath  = file.path(TABLES_DIR, "table_02b_l2_correlations.docx"),
    table_num = "2b",
    title     = "Between-Person Descriptive Statistics, Reliabilities, and Correlations."
)

# --- Table 2 combined variant (15x15 split-diagonal, landscape) ---------------
# Preserves original split-diagonal structure; committee may prefer single table.
n_all <- length(table2_vars)
cells2_comb <- matrix("",
    nrow = n_all, ncol = n_all,
    dimnames = list(table2_vars, table2_vars)
)
for (i in seq_len(n_all)) {
    ri <- table2_vars[i]
    for (j in seq_len(n_all)) {
        cj <- table2_vars[j]
        if (i == j) {
            om <- omega_all$omega[omega_all$variable == ri]
            cells2_comb[i, j] <- if (length(om) > 0) {
                paste0("(", fmt_r(om), ")")
            } else if (ri %in% no_omega_vars) {
                EMDASH
            } else {
                ""
            }
        } else if (i < j) {
            # Above diagonal: between-person Pearson on person-level scores
            # (corr_05 covers all 15 variables, including the L1 x L2 block)
            r_val <- get_corr(bp_mat, ri, cj)
            if (!is.na(r_val)) {
                cells2_comb[i, j] <- paste0(fmt_r(r_val), fmt_stars(get_corr(bp_pmat, ri, cj)))
            }
        } else {
            # Below diagonal: within-person rmcorr (L1 variables only;
            # L2 variables have no within-person estimate by design)
            if (ri %in% l1_vars && cj %in% l1_vars) {
                r_val <- get_corr(wp_mat, ri, cj)
                if (!is.na(r_val)) {
                    cells2_comb[i, j] <- paste0(fmt_r(r_val), fmt_stars(get_corr(wp_pmat, ri, cj)))
                }
            }
        }
    }
}

# Embed row number in Variable label (no separate stub column) to avoid 2-digit
# wrapping in a narrow stub cell.
t2_comb_rows <- purrr::map_dfr(seq_along(table2_vars), function(i) {
    v <- table2_vars[i]
    d <- desc_lookup[desc_lookup$variable == v, ]
    icc_v <- icc_lookup$icc_adjusted[icc_lookup$variable == v]
    row <- tibble::tibble(
        Variable = paste0(i, ". ", var_labels[v]),
        M        = if (nrow(d) > 0) as.character(d$mean) else "",
        SD       = if (nrow(d) > 0) as.character(d$sd) else "",
        ICC      = if (v %in% l1_vars && length(icc_v) > 0) fmt_r(icc_v) else ""
    )
    for (j in seq_along(table2_vars)) row[[as.character(j)]] <- cells2_comb[i, j]
    row
})

note2_comb <- paste0(
    "N = ", n_prs, " participants; n = ", n_obs, " observations. ",
    "Above diagonal: between-person Pearson correlations among person-level scores ",
    "(within-person variables averaged across the three timepoints; between-person ",
    "variables measured at intake). Below diagonal: within-person repeated-measures ",
    "correlations for within-person variables only (rmcorr; Bakdash & Marusich, 2017). ",
    "Diagonal entries in parentheses are McDonald's ω reliability coefficients ",
    "(within-level from MCFA for variables 1-10; single-level CFA for variables 11-15; ",
    "Lai, 2021). ICC = intraclass correlation from unconditional means model. ",
    EMDASH, " = single-item measure. PC = Psychological Contract. ",
    "* p < .05. ** p < .01. *** p < .001."
)

# Explicit column widths: 19 cols total, target 9.0 in landscape text width.
# Body and header at 9pt so starred negatives (e.g. "-.34***") fit a 0.435-in
# column without wrapping and "ICC" stays on one header line; the caption and
# note render at 12pt (caption via save_docx_table_landscape, note via
# add_apa_note props).
comb_corr_cols <- as.character(seq_along(table2_vars))
comb_col_widths <- c(
    Variable = 1.475, M = 0.36, SD = 0.36, ICC = 0.28,
    setNames(rep(0.435, length(comb_corr_cols)), comb_corr_cols)
)
# Total: 1.475 + 0.36 + 0.36 + 0.28 + 15*0.435 = 9.0 in
ft2_comb <- apa_flextable(t2_comb_rows, col_widths = comb_col_widths) |>
    flextable::fontsize(size = 9, part = "all") |>
    flextable::padding(
        padding.top = 2.5, padding.bottom = 2.5,
        padding.left = 1.5, padding.right = 1.5,
        part = "all"
    ) |>
    add_apa_note(note2_comb)
save_docx_table_landscape(
    ft2_comb,
    filepath  = file.path(TABLES_DIR, "table_02_combined_correlations.docx"),
    table_num = "2",
    title     = "Descriptive Statistics, Reliabilities, and Correlations (Combined Variant)."
)


# =============================================================================
# [3] TABLE 3: CONFIRMATORY FACTOR ANALYSIS RESULTS
# =============================================================================
log_msg("=== [3] Table 3: CFA Results ===")

fit_idx <- readr::read_csv(file.path(CFA_DIR, "cfa_01_fit_indices.csv"),
    show_col_types = FALSE
)
load_l2 <- readr::read_csv(file.path(CFA_DIR, "cfa_02_loadings_l2.csv"),
    show_col_types = FALSE
)
load_l1 <- readr::read_csv(file.path(CFA_DIR, "cfa_03_loadings_l1.csv"),
    show_col_types = FALSE
)

# Panel A: Fit indices
fit_display <- fit_idx |>
    dplyr::mutate(
        chi_sq_str = paste0(
            formatC(chi_sq, digits = 2, format = "f"),
            " (", df, ")"
        ),
        p_str = fmt_p(p),
        rmsea_str = paste0(
            formatC(rmsea, digits = 3, format = "f"),
            " [", formatC(rmsea_lo, digits = 3, format = "f"),
            ", ", formatC(rmsea_hi, digits = 3, format = "f"), "]"
        ),
        srmr_str = dplyr::case_when(
            !is.na(srmr) ~ formatC(srmr, digits = 3, format = "f"),
            !is.na(srmr_within) ~ paste0(
                formatC(srmr_within, digits = 3, format = "f"), " / ",
                formatC(srmr_between, digits = 3, format = "f")
            ),
            .default = EMDASH
        )
    ) |>
    dplyr::select(
        Model            = model,
        `χ² (df)`        = chi_sq_str,
        p                = p_str,
        CFI              = cfi,
        TLI              = tli,
        `RMSEA [90% CI]` = rmsea_str,
        `SRMR (W/B)`     = srmr_str
    )

ft3a <- apa_flextable(fit_display) |>
    add_apa_note(paste0(
        "L2 CFA = single-level confirmatory factor analysis for between-person scales. ",
        "L1 MCFA = multilevel CFA for within-person scales. Both models estimated with ",
        "maximum likelihood with robust (Huber-White) standard errors (MLR). ",
        "χ² = Satorra-Bentler scaled chi-square statistic. CFI = Comparative Fit Index. ",
        "TLI = Tucker-Lewis Index. RMSEA = Root Mean Square Error of Approximation. ",
        "SRMR = Standardized Root Mean Residual; W = within-level, B = between-level for MCFA. ",
        "Fit index cutoffs: CFI/TLI >= .95; RMSEA <= .06; SRMR <= .08 (Hu & Bentler, 1999)."
    ))

# Panel B: Standardized factor loadings
load_within <- load_l1 |>
    dplyr::filter(level == "L1_within") |>
    dplyr::select(factor, item, std_all, se, pvalue)

factor_order_l1 <- c("PF", "CW", "EE", "NF_COMP", "NF_AUTO", "NF_REL", "ATCB")
factor_order_l2 <- c("POS_AFF", "NEG_AFF", "PCB", "PCV")

factor_labels <- c(
    PF      = "Physical Fatigue",
    CW      = "Cognitive Weariness",
    EE      = "Emotional Exhaustion",
    NF_COMP = "Competence Frustration",
    NF_AUTO = "Autonomy Frustration",
    NF_REL  = "Relatedness Frustration",
    ATCB    = "Marker Variable (ATCB)",
    POS_AFF = "Positive Affect",
    NEG_AFF = "Negative Affect",
    PCB     = "PC Breach",
    PCV     = "PC Violation"
)

# Short column labels for the condensed wide-format loading table
factor_col_l1 <- c(
    PF = "PF", CW = "CW", EE = "EE",
    NF_COMP = "COMP", NF_AUTO = "AUTO", NF_REL = "REL",
    ATCB = "ATCB"
)
factor_col_l2 <- c(POS_AFF = "PA", NEG_AFF = "NA", PCB = "PCB", PCV = "PCV")

#' Format CFA loadings as long-format (item-per-row with lambda, SE, p)
#'
#' @param df           Data frame with columns factor, item, std_all, se, pvalue.
#' @param factor_order Character vector of factor names defining display order.
#' @return Tibble with columns Factor, Item, lambda, SE, p.
format_loadings_long <- function(df, factor_order) {
    df |>
        dplyr::filter(factor %in% factor_order) |>
        dplyr::mutate(
            factor = factor(factor, levels = factor_order),
            Factor = factor_labels[as.character(factor)]
        ) |>
        dplyr::arrange(factor) |>
        dplyr::select(
            Factor,
            Item = item,
            "λ" = std_all,
            SE = se,
            p = pvalue
        ) |>
        dplyr::mutate(p = fmt_p(p))
}

#' Format CFA loadings as wide (factor-as-column) layout
#'
#' Items are rows; each factor is a column; the lambda appears in the cell for its
#' factor and "" elsewhere. Omits SE and p (stated all p < .001 in the note).
#'
#' @param df           Data frame with columns factor, item, std_all.
#' @param factor_order Character vector of factor names defining column order.
#' @param col_labels   Named character vector mapping factor code to short column label.
#' @return Tibble with an Item column followed by one column per factor.
format_loadings_wide <- function(df, factor_order, col_labels) {
    df <- df |>
        dplyr::filter(factor %in% factor_order) |>
        dplyr::mutate(factor = factor(factor, levels = factor_order)) |>
        dplyr::arrange(factor, item)
    purrr::map_dfr(seq_len(nrow(df)), function(i) {
        r <- df[i, ]
        row <- tibble::tibble(Item = r$item)
        for (f in factor_order) {
            row[[col_labels[f]]] <- if (r$factor == f) fmt_r(r$std_all) else ""
        }
        row
    })
}

# --- Condensed wide-format loadings (primary, main-text Table 3 Panel B) ------
l1_wide <- format_loadings_wide(load_within, factor_order_l1, factor_col_l1)
l2_wide <- format_loadings_wide(load_l2, factor_order_l2, factor_col_l2)

note3b_condensed <- paste0(
    "Entries are standardized factor loadings (std.all). All loadings p < .001 ",
    "unless otherwise noted. ",
    "PF = Physical Fatigue; CW = Cognitive Weariness; EE = Emotional Exhaustion; ",
    "COMP = Competence Need Frustration; AUTO = Autonomy Need Frustration; ",
    "REL = Relatedness Need Frustration; ATCB = common method marker variable; ",
    "PA = Positive Affect; NA = Negative Affect; ",
    "PCB = Psychological Contract Breach; PCV = Psychological Contract Violation. ",
    "L1 loadings from MCFA within level; L2 loadings from single-level CFA (MLR)."
)

ft3b_l1 <- apa_flextable(l1_wide) |>
    add_apa_note(note3b_condensed)
ft3b_l2 <- apa_flextable(l2_wide)

# Main Table 3: fit indices + condensed loadings (two L1/L2 sub-panels for Panel B)
save_docx_tables(
    panels = list(
        list(label = "Panel A. Model Fit Indices", ft = ft3a),
        list(label = "Panel B. Within-Person (L1) Standardized Loadings", ft = ft3b_l1),
        list(label = "Panel B (cont.). Between-Person (L2) Standardized Loadings", ft = ft3b_l2)
    ),
    filepath = file.path(TABLES_DIR, "table_03_cfa_results.docx"),
    table_num = 3,
    title = "Confirmatory Factor Analysis Results."
)

# --- Full long-format loadings (appendix-A variant) ---------------------------
# NOTE: Item text (wording) is not available in pipeline CSVs; only item codes
# (e.g., pf1, pf2) are present. Add item text manually from the survey instrument
# before including this table in Appendix A.
l1_load_long <- format_loadings_long(load_within, factor_order_l1)
l2_load_long <- format_loadings_long(load_l2, factor_order_l2)

loadings_full <- dplyr::bind_rows(
    tibble::tibble(
        Factor = "L1 (Within-Person) Scale Items",
        Item = "", "λ" = NA_real_, SE = NA_real_, p = ""
    ),
    l1_load_long,
    tibble::tibble(
        Factor = "L2 (Between-Person) Scale Items",
        Item = "", "λ" = NA_real_, SE = NA_real_, p = ""
    ),
    l2_load_long
)

ft3_full <- apa_flextable(loadings_full) |>
    flextable::bold(i = which(loadings_full$Item == ""), j = 1) |>
    add_apa_note(paste0(
        "λ = standardized factor loading (std.all from lavaan). ",
        "SE = standard error. All loadings are statistically significant (p < .001) ",
        "unless otherwise noted. Item codes shown; add item text from survey instrument. ",
        "L1 = within-level MCFA; L2 = single-level CFA."
    ))

save_docx_tables(
    panels = list(
        list(label = "Factor Loadings (Full Item List)", ft = ft3_full)
    ),
    filepath = file.path(TABLES_DIR, "appendix_a_cfa_loadings_full.docx"),
    table_num = "A",
    title = "Standardized CFA Factor Loadings for All Items (Appendix A Variant)."
)


# =============================================================================
# [4a] TABLE 4a: MULTILEVEL MODEL RESULTS (M0-M6)
# =============================================================================
log_msg("=== [4a] Table 4a: MLM Results (M0-M6) ===")

fe_all <- readr::read_csv(file.path(MLM_DIR, "mlm_02_fixed_effects.csv"),
    show_col_types = FALSE
)
mc_all <- readr::read_csv(file.path(MLM_DIR, "mlm_01_model_comparison.csv"),
    show_col_types = FALSE
)
dr2 <- readr::read_csv(file.path(MLM_DIR, "mlm_07_delta_r2.csv"),
    show_col_types = FALSE
)

model_names_main <- c(
    "Model 0: Unconditional Means",
    "Model 1: Fixed Time",
    "Model 2: Random Slope",
    "Model 3: L1 Within-Person",
    "Model 4: L1 Within + Between",
    "Model 5: L1 + L2 Study Variables",
    "Model 6: Full Model with Covariates"
)
model_short <- c("M0", "M1", "M2", "M3", "M4", "M5", "M6")
names(model_short) <- model_names_main

# Ordered predictor display names (study-specific: meetings_time, recruitment)
term_labels <- c(
    "(Intercept)"                   = "Intercept",
    "time_c"                        = "Time (centered)",
    "pf_mean_within"                = "Physical Fatigue (WP)",
    "cw_mean_within"                = "Cognitive Weariness (WP)",
    "ee_mean_within"                = "Emotional Exhaustion (WP)",
    "comp_mean_within"              = "Competence Frustration (WP)",
    "auto_mean_within"              = "Autonomy Frustration (WP)",
    "relt_mean_within"              = "Relatedness Frustration (WP)",
    "meetings_count_within"         = "Meeting Count (WP)",
    "meetings_time_within"          = "Meeting Duration (WP)",
    "pf_mean_between"               = "Physical Fatigue (BP)",
    "cw_mean_between"               = "Cognitive Weariness (BP)",
    "ee_mean_between"               = "Emotional Exhaustion (BP)",
    "comp_mean_between"             = "Competence Frustration (BP)",
    "auto_mean_between"             = "Autonomy Frustration (BP)",
    "relt_mean_between"             = "Relatedness Frustration (BP)",
    "meetings_count_between"        = "Meeting Count (BP)",
    "meetings_time_between"         = "Meeting Duration (BP)",
    "recruitment_sourcesnowball"    = "Recruitment: Snowball",
    "br_mean_c"                     = "PC Breach",
    "vio_mean_c"                    = "PC Violation",
    "js_mean_c"                     = "Job Satisfaction",
    "pa_mean_c"                     = "Positive Affect",
    "na_mean_c"                     = "Negative Affect",
    "age_c"                         = "Age",
    "job_tenureLess than a year"    = "Tenure: < 1 yr",
    "job_tenure3 to 5 years"        = "Tenure: 3-5 yr",
    "job_tenureMore than 5 years"   = "Tenure: > 5 yr"
)

term_order <- names(term_labels)

fe_main <- fe_all |>
    dplyr::filter(model %in% model_names_main) |>
    dplyr::select(term, estimate, std.error, p.value, model) |>
    dplyr::mutate(
        cell = purrr::pmap_chr(
            list(estimate, std.error, p.value),
            function(b, se, p) fmt_est(b, se, p)
        ),
        model_short = model_short[model]
    )

fe_wide <- fe_main |>
    dplyr::filter(term %in% term_order) |>
    dplyr::mutate(
        term_label = term_labels[term],
        term_label = factor(term_label, levels = term_labels[term_order])
    ) |>
    dplyr::arrange(term_label) |>
    tidyr::pivot_wider(
        id_cols     = term_label,
        names_from  = model_short,
        values_from = cell,
        values_fill = ""
    ) |>
    dplyr::rename(Predictor = term_label)

# Variance components
vc_main <- mc_all |>
    dplyr::filter(Model %in% model_names_main) |>
    dplyr::mutate(
        model_short = model_short[Model],
        tau_00_str = formatC(tau_00, digits = 3, format = "f"),
        tau_11_str = ifelse(is.na(tau_11), "",
            formatC(tau_11, digits = 3, format = "f")
        ),
        sigma2_str = formatC(sigma2, digits = 3, format = "f"),
        R2m_str = formatC(R2_marginal, digits = 3, format = "f"),
        R2c_str = formatC(R2_conditional, digits = 3, format = "f"),
        AIC_str = formatC(AIC, digits = 1, format = "f")
    )

dr2_main <- dr2 |>
    dplyr::filter(Model %in% model_names_main) |>
    dplyr::mutate(
        model_short = model_short[Model],
        delta_R2m_str = ifelse(delta_R2_marginal == 0, "",
            formatC(delta_R2_marginal, digits = 3, format = "f")
        ),
        f2_str = ifelse(f2 == 0, "",
            paste0(
                formatC(f2, digits = 3, format = "f"),
                " (", f2_magnitude, ")"
            )
        )
    )

#' Build a single variance-component row for a publication table
#'
#' @param label      Character; row label shown in the Predictor column.
#' @param col_name   Character; name of the pre-formatted string column in tbl.
#' @param tbl        Data frame with model_short and col_name columns.
#' @param short_names Character vector of model short-names defining column order.
#' @return One-row tibble.
make_vc_row <- function(label, col_name, tbl, short_names) {
    row <- tibble::tibble(Predictor = label)
    for (mn in short_names) {
        val <- tbl[[col_name]][tbl$model_short == mn]
        row[[mn]] <- if (length(val) > 0) val else ""
    }
    row
}

short_main <- model_short

# Load standardized effects for Strategy 1 beta column
stdzd <- readr::read_csv(file.path(MLM_DIR, "mlm_05_standardized_effects.csv"),
    show_col_types = FALSE
)
beta_col <- intersect(
    c("Std_Coefficient", "beta", "std_beta", "standardized"),
    names(stdzd)
)[1]
key_col <- intersect(c("term", "Parameter"), names(stdzd))[1]
if (is.na(beta_col)) {
    log_msg("WARNING: beta column not found in mlm_05_standardized_effects.csv")
    beta_col <- key_col
}
stdzd_join <- stdzd |>
    dplyr::rename(term = !!key_col) |>
    dplyr::select(term, model, beta_val = !!beta_col)

# --- Strategy 1: M5 focal coefficient table + fit progression panel ----------

m5_name <- "Model 5: L1 + L2 Study Variables"
l1_term_keys <- c(
    "time_c",
    "pf_mean_within", "cw_mean_within", "ee_mean_within",
    "comp_mean_within", "auto_mean_within", "relt_mean_within",
    "meetings_count_within", "meetings_time_within"
)
l2_term_keys <- c(
    "pf_mean_between", "cw_mean_between", "ee_mean_between",
    "comp_mean_between", "auto_mean_between", "relt_mean_between",
    "meetings_count_between", "meetings_time_between",
    "recruitment_sourcesnowball",
    "br_mean_c", "vio_mean_c", "js_mean_c", "pa_mean_c", "na_mean_c"
)

fe_m5 <- fe_all |>
    dplyr::filter(model == m5_name, term %in% c(l1_term_keys, l2_term_keys)) |>
    dplyr::left_join(
        dplyr::filter(stdzd_join, model == m5_name) |> dplyr::select(term, beta_val),
        by = "term"
    ) |>
    dplyr::mutate(
        term_label = term_labels[term],
        level = dplyr::if_else(term %in% l1_term_keys, "L1", "L2"),
        sort_idx = dplyr::if_else(
            level == "L1",
            match(term, l1_term_keys),
            as.integer(length(l1_term_keys) + match(term, l2_term_keys))
        )
    ) |>
    dplyr::arrange(sort_idx) |>
    dplyr::mutate(
        B_cell   = purrr::pmap_chr(list(estimate, std.error, p.value), fmt_est),
        beta_str = dplyr::if_else(is.na(beta_val), "", fmt_r(beta_val)),
        p_str    = fmt_p(p.value)
    )

if (all(c("conf.low", "conf.high") %in% names(fe_m5))) {
    fe_m5 <- fe_m5 |>
        dplyr::mutate(CI_cell = purrr::pmap_chr(list(conf.low, conf.high), fmt_ci))
} else {
    fe_m5 <- fe_m5 |> dplyr::mutate(CI_cell = "")
}

make_s1_sep <- function(label) {
    tibble::tibble(
        Predictor = label, B = "", `95% CI` = "", "β" = "", p = ""
    )
}
make_s1_fe_row <- function(r) {
    tibble::tibble(
        Predictor = r$term_label, B = r$B_cell,
        `95% CI` = r$CI_cell, "β" = r$beta_str, p = r$p_str
    )
}
add_s1_vc <- function(label, val) {
    tibble::tibble(
        Predictor = label, B = val, `95% CI` = "", "β" = "", p = ""
    )
}

vc_m5 <- vc_main |> dplyr::filter(model_short == "M5")
l1_fe <- fe_m5 |> dplyr::filter(level == "L1")
l2_fe <- fe_m5 |> dplyr::filter(level == "L2")

t4_s1_df <- dplyr::bind_rows(
    make_s1_sep("Within-Person Predictors (L1, CWC)"),
    purrr::map_dfr(seq_len(nrow(l1_fe)), function(i) make_s1_fe_row(l1_fe[i, ])),
    make_s1_sep("Between-Person Predictors (L2, GMC)"),
    purrr::map_dfr(seq_len(nrow(l2_fe)), function(i) make_s1_fe_row(l2_fe[i, ])),
    make_s1_sep("Variance Components"),
    add_s1_vc(paste0(GREEK["tau_00"], " (person intercept)"), vc_m5$tau_00_str),
    add_s1_vc(
        paste0(GREEK["tau_11"], " (slope var.)"),
        dplyr::if_else(nzchar(vc_m5$tau_11_str), vc_m5$tau_11_str, EMDASH)
    ),
    add_s1_vc(paste0(GREEK["sigma2"], " (L1 residual)"), vc_m5$sigma2_str),
    add_s1_vc(GREEK["R2m"], vc_m5$R2m_str),
    add_s1_vc(GREEK["R2c"], vc_m5$R2c_str)
)

s1_sep_idx <- which(t4_s1_df$Predictor %in% c(
    "Within-Person Predictors (L1, CWC)",
    "Between-Person Predictors (L2, GMC)",
    "Variance Components"
))

ft4_s1 <- apa_flextable(t4_s1_df) |>
    flextable::bold(i = s1_sep_idx, j = 1) |>
    add_apa_note(paste0(
        "N = ", n_prs, " participants; n = ", n_obs, " observations. ",
        "Model 5 includes L1 within-person and L2 between-person study predictors. ",
        "WP = within-person (CWC); BP = between-person (GMC). ",
        "B = unstandardized coefficient with SE in parentheses; significance ",
        "stars attach to B. 95% CI = Wald interval; ",
        "β = standardized (Lorah, 2018). ",
        "* p < .05. ** p < .01. *** p < .001. ",
        "Variance component CIs require profile likelihood; point estimates shown. ",
        GREEK["R2m"], " and ", GREEK["R2c"],
        " from Nakagawa and Schielzeth (2013). ",
        "PC = Psychological Contract. Covariates (education, tenure) in Appendix D."
    ))

fit_panel_df <- dplyr::bind_rows(
    make_vc_row("AIC", "AIC_str", vc_main, short_main),
    make_vc_row(GREEK["R2m"], "R2m_str", vc_main, short_main),
    make_vc_row(GREEK["R2c"], "R2c_str", vc_main, short_main),
    make_vc_row(paste0("Δ", GREEK["R2m"]), "delta_R2m_str", dr2_main, short_main),
    make_vc_row("Cohen's f²", "f2_str", dr2_main, short_main)
) |>
    dplyr::rename(Index = Predictor) |>
    dplyr::mutate(dplyr::across(-Index, ~ dplyr::if_else(. == "", EMDASH, .)))
ft4_s1_fit <- apa_flextable(fit_panel_df)

save_docx_tables(
    panels = list(
        list(label = "Panel A. Model 5 Fixed Effects and Variance Components", ft = ft4_s1),
        list(label = "Panel B. Model Fit Progression (M0-M6)", ft = ft4_s1_fit)
    ),
    filepath = file.path(TABLES_DIR, "table_04_s1_m5_focal.docx"),
    table_num = "4",
    title = "Multilevel Model Results: M5 Focal with Fit Progression (Strategy 1)."
)

# --- Strategy 2: Split sequence M0-M3 / M4-M6 --------------------------------
vc_block <- dplyr::bind_rows(
    make_vc_row(paste0(GREEK["tau_00"], " (intercept var.)"), "tau_00_str", vc_main, short_main),
    make_vc_row(paste0(GREEK["tau_11"], " (slope var.)"), "tau_11_str", vc_main, short_main),
    make_vc_row(paste0(GREEK["sigma2"], " (L1 residual)"), "sigma2_str", vc_main, short_main),
    make_vc_row(GREEK["R2m"], "R2m_str", vc_main, short_main),
    make_vc_row(GREEK["R2c"], "R2c_str", vc_main, short_main),
    make_vc_row("AIC", "AIC_str", vc_main, short_main),
    make_vc_row(paste0("Δ", GREEK["R2m"]), "delta_R2m_str", dr2_main, short_main),
    make_vc_row("Cohen's f²", "f2_str", dr2_main, short_main)
)

# Em dash marks structurally absent cells (predictor not in that model)
dash_empty <- function(df) {
    dplyr::mutate(df, dplyr::across(-Predictor, ~ dplyr::if_else(. == "", EMDASH, .)))
}

# M0-M3
s2_m0m3 <- c("M0", "M1", "M2", "M3")
fe_m0m3 <- fe_wide |>
    dplyr::select(Predictor, dplyr::any_of(s2_m0m3)) |>
    dash_empty()
vc_m0m3 <- vc_block |>
    dplyr::select(Predictor, dplyr::any_of(s2_m0m3)) |>
    dash_empty()
sep_m0m3 <- tibble::tibble(Predictor = "Variance Components and Fit")
for (mn in s2_m0m3) sep_m0m3[[mn]] <- ""
t4_s2a_df <- dplyr::bind_rows(fe_m0m3, sep_m0m3, vc_m0m3)
ft4_s2a <- apa_flextable(t4_s2a_df) |>
    flextable::bold(
        i = which(t4_s2a_df$Predictor == "Variance Components and Fit"), j = 1
    ) |>
    add_apa_note(paste0(
        "N = ", n_prs, " participants; n = ", n_obs, " observations. ",
        "M0 = unconditional means; M1 = fixed time effect; M2 = random slope; ",
        "M3 = L1 within-person predictors. Cells show unstandardized B (SE); significance stars attach to B. ",
        EMDASH, " = predictor or statistic not included in the model. ",
        "* p < .05. ** p < .01. *** p < .001. WP = within-person (CWC)."
    ))
save_docx_table(
    ft4_s2a,
    filepath  = file.path(TABLES_DIR, "table_04_s2a_m0m3.docx"),
    table_num = "4a",
    title     = "Multilevel Model Results: Strategy 2, Models 0-3."
)

# Compact variant: only predictors estimated in at least one of M0-M3; the
# omitted blocks are documented in the note. The full-grid variant above is
# retained for committee members who prefer the complete sequence layout.
fe_m0m3_compact <- fe_m0m3 |>
    dplyr::filter(!dplyr::if_all(-Predictor, ~ . == EMDASH))
t4_s2a_c_df <- dplyr::bind_rows(fe_m0m3_compact, sep_m0m3, vc_m0m3)
ft4_s2a_c <- apa_flextable(t4_s2a_c_df) |>
    flextable::bold(
        i = which(t4_s2a_c_df$Predictor == "Variance Components and Fit"), j = 1
    ) |>
    add_apa_note(paste0(
        "N = ", n_prs, " participants; n = ", n_obs, " observations. ",
        "Only predictors estimated in at least one of M0-M3 are shown; ",
        "between-person (BP) means enter at M4, L2 study variables ",
        "(psychological contract, job satisfaction, affect) at M5, and ",
        "demographic covariates at M6 (see Table 4b). ",
        "M0 = unconditional means; M1 = fixed time effect; M2 = random slope; ",
        "M3 = L1 within-person predictors. ",
        "Cells show unstandardized B (SE); significance stars attach to B. ",
        EMDASH, " = predictor or statistic not included in the model. ",
        "* p < .05. ** p < .01. *** p < .001. WP = within-person (CWC)."
    ))
save_docx_table(
    ft4_s2a_c,
    filepath  = file.path(TABLES_DIR, "table_04_s2a_m0m3_compact.docx"),
    table_num = "4a",
    title     = "Multilevel Model Results: Strategy 2, Models 0-3 (Compact Variant)."
)

# M4-M6
s2_m4m6 <- c("M4", "M5", "M6")
fe_m4m6 <- fe_wide |>
    dplyr::select(Predictor, dplyr::any_of(s2_m4m6)) |>
    dash_empty()
vc_m4m6 <- vc_block |>
    dplyr::select(Predictor, dplyr::any_of(s2_m4m6)) |>
    dash_empty()
sep_m4m6 <- tibble::tibble(Predictor = "Variance Components and Fit")
for (mn in s2_m4m6) sep_m4m6[[mn]] <- ""
t4_s2b_df <- dplyr::bind_rows(fe_m4m6, sep_m4m6, vc_m4m6)
ft4_s2b <- apa_flextable(t4_s2b_df) |>
    flextable::bold(
        i = which(t4_s2b_df$Predictor == "Variance Components and Fit"), j = 1
    ) |>
    add_apa_note(paste0(
        "N = ", n_prs, " participants; n = ", n_obs, " observations. ",
        "M4 = L1 within + between-person; M5 = adds L2 study predictors; ",
        "M6 = adds demographic covariates. Cells show unstandardized B (SE); significance stars attach to B. ",
        EMDASH, " = predictor or statistic not included in the model. ",
        "* p < .05. ** p < .01. *** p < .001. ",
        "WP = within-person (CWC); BP = between-person (GMC). ",
        "PC = Psychological Contract. Education and tenure dummies in Appendix D."
    ))
save_docx_table(
    ft4_s2b,
    filepath  = file.path(TABLES_DIR, "table_04_s2b_m4m6.docx"),
    table_num = "4b",
    title     = "Multilevel Model Results: Strategy 2, Models 4-6."
)


# =============================================================================
# [4b] TABLE 4b: MODERATION MODELS (M7a/M7b)
# =============================================================================
log_msg("=== [4b] Table 4b: Moderation Models (M7a/M7b) ===")

model_names_mod <- c(
    "Model 7a: Count x Composites",
    "Model 7b: Time x Composites"
)
model_short_mod <- c("M7a", "M7b")
names(model_short_mod) <- model_names_mod

mc_mod <- readr::read_csv(file.path(MLM_DIR, "mlm_01b_phase6_comparison.csv"),
    show_col_types = FALSE
)

term_labels_mod <- c(
    "(Intercept)"                               = "Intercept",
    "time_c"                                    = "Time (centered)",
    "burnout_mean_within"                       = "Burnout Composite (WP)",
    "nf_mean_within"                            = "NF Composite (WP)",
    "burnout_mean_between"                      = "Burnout Composite (BP)",
    "nf_mean_between"                           = "NF Composite (BP)",
    "meetings_count_within"                     = "Meeting Count (WP)",
    "meetings_time_within"                      = "Meeting Duration (WP)",
    "meetings_count_between"                    = "Meeting Count (BP)",
    "meetings_time_between"                     = "Meeting Duration (BP)",
    "burnout_mean_within:meetings_count_within" = "Burnout × Meeting Count (WP)",
    "nf_mean_within:meetings_count_within"      = "NF × Meeting Count (WP)",
    "burnout_mean_within:meetings_time_within"  = "Burnout × Meeting Duration (WP)",
    "nf_mean_within:meetings_time_within"       = "NF × Meeting Duration (WP)",
    "recruitment_sourcesnowball"                = "Recruitment: Snowball",
    "br_mean_c"                                 = "PC Breach",
    "vio_mean_c"                                = "PC Violation",
    "js_mean_c"                                 = "Job Satisfaction",
    "pa_mean_c"                                 = "Positive Affect",
    "na_mean_c"                                 = "Negative Affect",
    "age_c"                                     = "Age"
)

fe_mod <- fe_all |>
    dplyr::filter(model %in% model_names_mod) |>
    dplyr::select(term, estimate, std.error, p.value, model) |>
    dplyr::mutate(
        cell = purrr::pmap_chr(
            list(estimate, std.error, p.value),
            function(b, se, p) fmt_est(b, se, p)
        ),
        model_short = model_short_mod[model]
    ) |>
    dplyr::filter(term %in% names(term_labels_mod)) |>
    dplyr::mutate(
        term_label = term_labels_mod[term],
        term_label = factor(term_label, levels = term_labels_mod)
    ) |>
    dplyr::arrange(term_label) |>
    tidyr::pivot_wider(
        id_cols     = term_label,
        names_from  = model_short,
        values_from = cell,
        values_fill = ""
    ) |>
    dplyr::rename(Predictor = term_label)

vc_mod <- mc_mod |>
    dplyr::filter(Model %in% model_names_mod) |>
    dplyr::mutate(
        model_short = model_short_mod[Model],
        tau_00_str = formatC(tau_00, digits = 3, format = "f"),
        sigma2_str = formatC(sigma2, digits = 3, format = "f"),
        R2m_str = formatC(R2_marginal, digits = 3, format = "f"),
        R2c_str = formatC(R2_conditional, digits = 3, format = "f"),
        AIC_str = formatC(AIC, digits = 1, format = "f"),
        LRT_p_str = fmt_p(LRT_p),
        LRT_str = paste0(
            formatC(LRT_chi2, digits = 2, format = "f"),
            " (df = ", LRT_df, "), p ",
            dplyr::if_else(
                startsWith(LRT_p_str, "<"), LRT_p_str, paste0("= ", LRT_p_str)
            )
        )
    )

sep_row_mod <- tibble::tibble(Predictor = "Variance Components", M7a = "", M7b = "")
vc_block_mod <- dplyr::bind_rows(
    make_vc_row(paste0(GREEK["tau_00"], " (L2 intercept var.)"), "tau_00_str", vc_mod, model_short_mod),
    make_vc_row(paste0(GREEK["sigma2"], " (L1 residual var.)"), "sigma2_str", vc_mod, model_short_mod),
    make_vc_row(GREEK["R2m"], "R2m_str", vc_mod, model_short_mod),
    make_vc_row(GREEK["R2c"], "R2c_str", vc_mod, model_short_mod),
    make_vc_row("AIC", "AIC_str", vc_mod, model_short_mod),
    make_vc_row("LRT vs. base (χ², df, p)", "LRT_str", vc_mod, model_short_mod)
)

fe_mod <- dash_empty(fe_mod)
t4b_df <- dplyr::bind_rows(fe_mod, sep_row_mod, vc_block_mod)

ft4b <- apa_flextable(t4b_df) |>
    flextable::bold(
        i = which(t4b_df$Predictor == "Variance Components"),
        j = 1
    ) |>
    add_apa_note(paste0(
        "WP = within-person; BP = between-person. NF = Need Frustration. ",
        "M7a tests meeting count as the moderator; M7b tests meeting duration (minutes). ",
        "Burnout composite = mean of Physical Fatigue, Cognitive Weariness, and Emotional ",
        "Exhaustion (WP-centered). NF composite = mean of Competence, Autonomy, and ",
        "Relatedness Frustration (WP-centered). ",
        "LRT = likelihood ratio test vs. composite main-effects model (no interactions). ",
        EMDASH, " = term not included in the model. ",
        "Composite aggregation may obscure facet-specific moderation ",
        "(e.g., an EE-specific interaction); see text for discussion. ",
        "* p < .05. ** p < .01. *** p < .001."
    ))

save_docx_table(
    ft4b,
    filepath  = file.path(TABLES_DIR, "table_04b_moderation.docx"),
    table_num = "4b",
    title     = "Moderation Models: Meeting Load × Burnout/NF Composites (M7a-M7b)."
)


# =============================================================================
# [5] TABLE 5: HYPOTHESIS TEST SUMMARY
# =============================================================================
log_msg("=== [5] Table 5: Hypothesis Test Summary ===")

hyp <- readr::read_csv(file.path(MLM_DIR, "mlm_04_hypothesis_tests.csv"),
    show_col_types = FALSE
)
std_fx <- readr::read_csv(file.path(MLM_DIR, "mlm_05_standardized_effects.csv"),
    show_col_types = FALSE
)
ps_d <- readr::read_csv(file.path(MLM_DIR, "mlm_06_level_specific_es.csv"),
    show_col_types = FALSE
)

std_lookup <- std_fx |>
    dplyr::select(model, term = Parameter, beta = Std_Coefficient) |>
    dplyr::mutate(beta = round(beta, 3))

pd_lookup <- ps_d |>
    dplyr::filter(level %in% c("L1 (within)", "L2 (between)")) |>
    dplyr::select(model, term, pseudo_d) |>
    dplyr::mutate(pseudo_d = round(pseudo_d, 3))

t5 <- hyp |>
    dplyr::left_join(std_lookup,
        by = c("model_name" = "model", "term" = "term")
    ) |>
    dplyr::left_join(pd_lookup,
        by = c("model_name" = "model", "term" = "term")
    ) |>
    dplyr::mutate(
        description = gsub("->", "→", description, fixed = TRUE),
        description = gsub(" x ", " × ", description, fixed = TRUE),
        model_name = gsub(" x ", " × ", model_name, fixed = TRUE),
        B = ifelse(is.na(Estimate) | hypothesis == "Prereq", "",
            formatC(Estimate, digits = 3, format = "f")
        ),
        p = ifelse(is.na(p_value), "", fmt_p(p_value)),
        beta = ifelse(is.na(beta), "", formatC(beta, digits = 3, format = "f")),
        d = ifelse(is.na(pseudo_d), "", formatC(pseudo_d, digits = 3, format = "f"))
    ) |>
    dplyr::select(
        Hypothesis = hypothesis,
        Description = description,
        Model = model_name,
        B,
        "β" = beta,
        d,
        p,
        Supported
    )

# Group rows under hypothesis-block subheadings (bold separator rows)
t5_block_of <- function(h) {
    dplyr::case_when(
        startsWith(h, "H1") ~ "Need Frustration (H1)",
        startsWith(h, "H2") ~ "Burnout (H2)",
        startsWith(h, "H3") ~ "Meeting Load Moderation (H3)",
        startsWith(h, "H4") | startsWith(h, "H5") ~
            "Psychological Contract and Job Satisfaction (H4, H5)",
        TRUE ~ NA_character_
    )
}
make_t5_sep <- function(label) {
    tibble::tibble(
        Hypothesis = label, Description = "", Model = "",
        B = "", "β" = "", d = "", p = "", Supported = ""
    )
}
t5_blocks <- c(
    "Need Frustration (H1)", "Burnout (H2)", "Meeting Load Moderation (H3)",
    "Psychological Contract and Job Satisfaction (H4, H5)"
)
t5 <- dplyr::bind_rows(
    dplyr::filter(t5, is.na(t5_block_of(Hypothesis))),
    purrr::map_dfr(t5_blocks, function(b) {
        dplyr::bind_rows(
            make_t5_sep(b),
            dplyr::filter(t5, !is.na(t5_block_of(Hypothesis)) & t5_block_of(Hypothesis) == b)
        )
    })
)
t5_sep_idx <- which(t5$Hypothesis %in% t5_blocks)

ft5 <- apa_flextable(t5) |>
    flextable::bold(i = t5_sep_idx, j = 1) |>
    add_apa_note(paste0(
        "B = unstandardized regression coefficient. β = standardized coefficient ",
        "(parameters package). d = level-specific pseudo-d effect size (Lorah, 2018). ",
        "Hypothesis supported requires correct directional sign AND p < .05 ",
        "(one-tailed directional test). Moderation hypotheses (H3a/H3b) require p < .05 ",
        "(two-tailed). WP = within-person; BP = between-person. ",
        "PC = Psychological Contract. NF = Need Frustration."
    ))

save_docx_table(
    ft5,
    filepath  = file.path(TABLES_DIR, "table_05_hypothesis_tests.docx"),
    table_num = 5,
    title     = "Summary of Hypothesis Tests."
)


# =============================================================================
# [6] APPENDIX TABLES: CMV/INVARIANCE (Appendix B) + FULL M6 (Appendix D)
# =============================================================================
log_msg("=== [6] Appendix Tables ===")

# --- Appendix B: Measurement Invariance and Common Method Bias ---------------

mkr_ev <- readr::read_csv(file.path(CFA_DIR, "cfa_05_marker_evidence.csv"), show_col_types = FALSE)
mkr_fit <- readr::read_csv(file.path(CFA_DIR, "cfa_06_marker_fit.csv"), show_col_types = FALSE)
inv <- readr::read_csv(file.path(CFA_DIR, "cfa_08_metric_invariance.csv"), show_col_types = FALSE)

var_labels_mkr <- c(
    pf_mean                 = "Physical Fatigue",
    cw_mean                 = "Cognitive Weariness",
    ee_mean                 = "Emotional Exhaustion",
    comp_mean               = "Competence Frustration",
    auto_mean               = "Autonomy Frustration",
    relt_mean               = "Relatedness Frustration",
    turnover_intention_mean = "Turnover Intention"
)

mkr_ev_df <- mkr_ev |>
    dplyr::mutate(
        Variable    = dplyr::coalesce(var_labels_mkr[variable], variable),
        r           = fmt_r(rmcorr_r),
        `Near Zero` = ifelse(near_zero, "Yes", "No")
    ) |>
    dplyr::select(Variable, r, `Near Zero`)

ft_b1 <- apa_flextable(mkr_ev_df) |>
    add_apa_note(paste0(
        "r = repeated-measures correlation (rmcorr) between ATCB marker and each L1 variable. ",
        "Near-zero criterion: |r| < .10. All associations near-zero indicates the ",
        "marker variable is unrelated to substantive constructs."
    ))

fmt_possibly_na <- function(x, fmt_fn) {
    val <- suppressWarnings(as.numeric(x))
    dplyr::if_else(is.na(val), EMDASH, fmt_fn(val))
}

mkr_fit_df <- mkr_fit |>
    dplyr::mutate(
        "χ²"     = sprintf("%.2f", chi_sq),
        CFI      = fmt_r(cfi),
        RMSEA    = fmt_r(rmsea, digits = 3),
        `SRMR-W` = fmt_r(srmr_within, digits = 3),
        `SRMR-B` = fmt_r(srmr_between, digits = 3),
        "Δχ²"    = fmt_possibly_na(delta_chisq, function(v) sprintf("%.2f", v)),
        "Δdf"    = fmt_possibly_na(delta_df, function(v) as.character(as.integer(v))),
        p        = fmt_possibly_na(p_diff, fmt_p)
    ) |>
    dplyr::select(Model = model, "χ²", df, CFI, RMSEA, `SRMR-W`, `SRMR-B`, "Δχ²", "Δdf", p)

ft_b2 <- apa_flextable(mkr_fit_df) |>
    add_apa_note(paste0(
        "SRMR-W = within-level SRMR; SRMR-B = between-level SRMR. ",
        "Method-U = ATCB cross-loadings at L1. Method-R = cross-loadings plus fixed L1 factor covariances. ",
        "Δχ² = Satorra-Bentler scaled chi-square difference; Δdf = degrees of freedom difference. ",
        "χ² and fit indices from lavaan (Rosseel, 2012)."
    ))

inv_df <- inv |>
    dplyr::mutate(
        "χ²"    = sprintf("%.2f", chi2),
        "Δχ²"   = fmt_possibly_na(delta_chi2, function(v) sprintf("%.2f", v)),
        "Δdf"   = fmt_possibly_na(delta_df, function(v) as.character(as.integer(v))),
        p       = fmt_possibly_na(p_diff, fmt_p),
        Result  = dplyr::if_else(is.na(result) | result == "NA", EMDASH, as.character(result))
    ) |>
    dplyr::select(Model = model, "χ²", df, "Δχ²", "Δdf", p, Result)

ft_b3 <- apa_flextable(inv_df) |>
    add_apa_note(paste0(
        "Configural model = factor structure only (no equality constraints). ",
        "Metric model = factor loadings constrained equal across timepoints. ",
        "Δχ² = Satorra-Bentler scaled chi-square difference. ",
        "Metric invariance is supported when p > .05 (non-significant decrement in fit)."
    ))

save_docx_tables(
    list(
        list(label = "Panel A. ATCB Marker Correlations with Study Variables", ft = ft_b1),
        list(label = "Panel B. CMV Sensitivity Model Comparison", ft = ft_b2),
        list(label = "Panel C. Metric Invariance Tests", ft = ft_b3)
    ),
    filepath = file.path(TABLES_DIR, "appendix_b_measurement_checks.docx"),
    table_num = "B",
    title = "Measurement Invariance and Common Method Bias Checks."
)

# --- Appendix D: Full M6 Fixed Effects (all covariates) ----------------------

m6_name <- "Model 6: Full Model with Covariates"

term_labels_m6 <- c(
    term_labels,
    des_mean_c = "Desirability of Movement (BP)",
    jis_mean_c = "Job Insecurity (BP)"
)

fe_m6 <- fe_all |>
    dplyr::filter(model == m6_name, term %in% names(term_labels_m6)) |>
    dplyr::mutate(
        label   = term_labels_m6[term],
        sort_i  = match(term, names(term_labels_m6)),
        B_cell  = purrr::pmap_chr(list(estimate, std.error, p.value), fmt_est),
        CI_cell = purrr::pmap_chr(list(conf.low, conf.high), fmt_ci)
    ) |>
    dplyr::arrange(sort_i) |>
    dplyr::select(Predictor = label, `B (SE)` = B_cell, `95% CI` = CI_cell)

ft_d <- apa_flextable(fe_m6) |>
    add_apa_note(paste0(
        "Model 6 adds demographic covariates to the study-variable model (M5). ",
        "B = unstandardized coefficient; SE = standard error (in parentheses). ",
        "95% CI = Wald confidence interval. WP = within-person (CWC); BP = between-person (GMC). ",
        "DES = Desirability of Movement; JIS = Job Insecurity Scale. ",
        "* p < .05. ** p < .01. *** p < .001."
    ))

save_docx_table(
    ft_d,
    filepath  = file.path(TABLES_DIR, "appendix_d_m6_covariates.docx"),
    table_num = "D",
    title     = "Full Fixed Effects for Model 6 With Demographic Covariates."
)

log_msg("SKIPPED Appendix A: item-text not in any figs CSV (codes only); add manually from survey instrument.")
log_msg("SKIPPED Appendix C: power analysis lives in run_power_analysis/ pillar; out of scope for this script.")
log_msg("SKIPPED Appendix E: VIF diagnostics persisted as SVG only in multilevel_model.r; no CSV source.")


log_msg("=== Publication tables complete. Output -> ", TABLES_DIR, " ===")
