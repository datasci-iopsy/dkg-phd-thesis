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
        file.path(CORR_DIR, "corr_01_l2_pearson_matrix.csv"),
        file.path(CORR_DIR, "corr_03_mlm_between_matrix.csv"),
        file.path(CORR_DIR, "corr_04_rmcorr_within_matrix.csv"),
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
    ) |>
    gtsummary::modify_footnote(
        stat_0 ~ "Mean (SD) for continuous variables; n (%) for categorical variables."
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
    flextable::fit_to_width(max_width = APA_PAGE_W)

save_docx_table(
    ft1,
    filepath  = file.path(TABLES_DIR, "table_01_demographics.docx"),
    table_num = 1,
    title     = "Participant Demographics and Sample Characteristics"
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

bp_mat <- read_matrix(file.path(CORR_DIR, "corr_03_mlm_between_matrix.csv"))
wp_mat <- read_matrix(file.path(CORR_DIR, "corr_04_rmcorr_within_matrix.csv"))
l2_mat <- read_matrix(file.path(CORR_DIR, "corr_01_l2_pearson_matrix.csv"))

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
desc_lookup <- desc |>
    dplyr::select(variable, mean, sd) |>
    dplyr::mutate(dplyr::across(c(mean, sd), ~ round(., 2)))

icc_lookup <- iccs |>
    dplyr::select(variable, icc_adjusted) |>
    dplyr::mutate(icc_adjusted = round(icc_adjusted, 2))

# Build character correlation cell matrix
n_vars <- length(table2_vars)
corr_cells <- matrix("",
    nrow = n_vars, ncol = n_vars,
    dimnames = list(table2_vars, table2_vars)
)

#' Look up a single cell from a named correlation matrix
#'
#' @param mat Numeric matrix with row and column names.
#' @param r   Character; row name.
#' @param c   Character; column name.
#' @return Numeric correlation value, or NA_real_ if absent.
get_corr <- function(mat, r, c) {
    if (r %in% rownames(mat) && c %in% colnames(mat)) mat[r, c] else NA_real_
}

for (i in seq_along(table2_vars)) {
    ri <- table2_vars[i]
    for (j in seq_along(table2_vars)) {
        cj <- table2_vars[j]
        if (i == j) {
            om <- omega_all$omega[omega_all$variable == ri]
            corr_cells[i, j] <- if (length(om) > 0) {
                paste0("(", fmt_r(om), ")")
            } else if (ri %in% no_omega_vars) {
                "--"
            } else {
                ""
            }
        } else if (i < j) {
            # Above diagonal: between-person correlations
            r_val <- get_corr(bp_mat, ri, cj)
            if (is.na(r_val)) r_val <- get_corr(l2_mat, ri, cj)
            corr_cells[i, j] <- if (!is.na(r_val)) fmt_r(r_val) else ""
        } else {
            # Below diagonal: within-person correlations (L1 only)
            if (ri %in% l1_vars && cj %in% l1_vars) {
                r_val <- get_corr(wp_mat, ri, cj)
                corr_cells[i, j] <- if (!is.na(r_val)) fmt_r(r_val) else ""
            }
        }
    }
}

# Assemble Table 2 data frame
n_obs <- max(desc$n[desc$level == "L1"], na.rm = TRUE)
n_prs <- max(desc$n[desc$level == "L2"], na.rm = TRUE)

t2_rows <- purrr::map_dfr(seq_along(table2_vars), function(i) {
    v <- table2_vars[i]
    d <- desc_lookup[desc_lookup$variable == v, ]
    icc_v <- icc_lookup$icc_adjusted[icc_lookup$variable == v]

    row <- tibble::tibble(
        ` `      = as.character(i),
        Variable = var_labels[v],
        M        = if (nrow(d) > 0) as.character(d$mean) else "",
        SD       = if (nrow(d) > 0) as.character(d$sd) else "",
        ICC      = if (v %in% l1_vars && length(icc_v) > 0) fmt_r(icc_v) else ""
    )
    for (j in seq_along(table2_vars)) row[[as.character(j)]] <- corr_cells[i, j]
    row
})

note_n <- paste0(
    "N = ", n_prs, " participants; n = ", n_obs, " observations (3 timepoints per person). ",
    "Between-person correlations (above diagonal) are multilevel decomposed ",
    "(correlation package, multilevel = TRUE). Within-person correlations ",
    "(below diagonal, L1 variables only) are repeated-measures correlations ",
    "(rmcorr; Bakdash & Marusich, 2017). Diagonal entries in parentheses are ",
    "McDonald's omega reliability coefficients. ICC = intraclass correlation ",
    "coefficient from an unconditional means model. -- indicates single-item ",
    "measure (omega not estimable). PC = Psychological Contract."
)

ft2 <- apa_flextable(t2_rows) |>
    add_apa_note(note_n)

save_docx_table(
    ft2,
    filepath  = file.path(TABLES_DIR, "table_02_descriptives_correlations.docx"),
    table_num = 2,
    title     = "Descriptive Statistics, Reliability Estimates, and Correlations"
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
            .default = ""
        )
    ) |>
    dplyr::select(
        Model            = model,
        `chi2 (df)`      = chi_sq_str,
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
        "chi2 = Satorra-Bentler scaled chi-square statistic. CFI = Comparative Fit Index. ",
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

#' Format a CFA loadings data frame for publication table display
#'
#' @param df           Data frame with columns factor, item, std_all, se, pvalue.
#' @param factor_order Character vector of factor names defining display order.
#' @return Tibble with columns Factor, Item, lambda, SE, p.
format_loadings <- function(df, factor_order) {
    df |>
        dplyr::filter(factor %in% factor_order) |>
        dplyr::mutate(
            factor = factor(factor, levels = factor_order),
            Factor = factor_labels[as.character(factor)]
        ) |>
        dplyr::arrange(factor) |>
        dplyr::select(
            Factor,
            Item   = item,
            lambda = std_all,
            SE     = se,
            p      = pvalue
        ) |>
        dplyr::mutate(p = fmt_p(p))
}

l1_load_df <- format_loadings(load_within, factor_order_l1)
l2_load_df <- format_loadings(load_l2, factor_order_l2)

loadings_combined <- dplyr::bind_rows(
    tibble::tibble(
        Factor = "L1 (Within-Person) Scale Items",
        Item = "", lambda = NA_real_, SE = NA_real_, p = ""
    ),
    l1_load_df,
    tibble::tibble(
        Factor = "L2 (Between-Person) Scale Items",
        Item = "", lambda = NA_real_, SE = NA_real_, p = ""
    ),
    l2_load_df
)

ft3b <- apa_flextable(loadings_combined) |>
    flextable::bold(i = which(loadings_combined$Item == ""), j = 1) |>
    add_apa_note(paste0(
        "lambda = standardized factor loading (std.all from lavaan). ",
        "SE = standard error. All loadings are statistically significant (p < .001) ",
        "unless otherwise noted. Between-level MCFA loadings available on request."
    ))

# Combine panels A and B into one document
out3 <- file.path(TABLES_DIR, "table_03_cfa_results.docx")
doc3 <- officer::read_docx()
doc3 <- officer::body_add_par(doc3, "Table 3", style = "Normal")
doc3 <- officer::body_add_par(doc3,
    "Confirmatory Factor Analysis Results",
    style = "Normal"
)
doc3 <- officer::body_add_par(doc3, "Panel A. Model Fit Indices", style = "Normal")
doc3 <- flextable::body_add_flextable(doc3, ft3a)
doc3 <- officer::body_add_par(doc3, "", style = "Normal")
doc3 <- officer::body_add_par(doc3,
    "Panel B. Standardized Factor Loadings",
    style = "Normal"
)
doc3 <- flextable::body_add_flextable(doc3, ft3b)
doc3 <- officer::body_end_section_portrait(doc3)
print(doc3, target = out3)
log_msg("Saved: ", out3)


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

vc_block <- dplyr::bind_rows(
    make_vc_row("tau_00 (L2 intercept var.)", "tau_00_str", vc_main, short_main),
    make_vc_row("tau_11 (L2 slope var.)", "tau_11_str", vc_main, short_main),
    make_vc_row("sigma2 (L1 residual var.)", "sigma2_str", vc_main, short_main),
    make_vc_row("R2 marginal", "R2m_str", vc_main, short_main),
    make_vc_row("R2 conditional", "R2c_str", vc_main, short_main),
    make_vc_row("AIC", "AIC_str", vc_main, short_main),
    make_vc_row("Delta-R2 marginal", "delta_R2m_str", dr2_main, short_main),
    make_vc_row("Cohen's f2 (delta-R2m)", "f2_str", dr2_main, short_main)
)

sep_row <- tibble::tibble(Predictor = "Variance Components")
for (mn in short_main) sep_row[[mn]] <- ""

t4a_df <- dplyr::bind_rows(fe_wide, sep_row, vc_block)

ft4a <- apa_flextable(t4a_df) |>
    flextable::bold(
        i = which(t4a_df$Predictor == "Variance Components"),
        j = 1
    ) |>
    add_apa_note(paste0(
        "N = ", n_prs, " participants; n = ", n_obs, " observations. ",
        "WP = within-person (person-mean centered); BP = between-person (grand-mean centered ",
        "person means). Recruitment: Snowball = snowball/referral vs. CloudResearch (reference). ",
        "Cells show B (SE). * p < .05. ** p < .01. *** p < .001. ",
        "ML used for likelihood ratio tests; REML used for parameter estimates. ",
        "R2 marginal and conditional from Nakagawa & Schielzeth (2013). ",
        "Delta-R2 and Cohen's f2 based on marginal R2 change from previous model. ",
        "PC = Psychological Contract. ",
        "Note: Education level and job tenure dummy codes omitted from M6 for space; ",
        "full covariate results available in Appendix."
    ))

save_docx_table(
    ft4a,
    filepath  = file.path(TABLES_DIR, "table_04a_mlm_results.docx"),
    table_num = "4a",
    title     = "Multilevel Model Results for Turnover Intentions (Models 0-6)"
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
    "burnout_mean_within:meetings_count_within" = "Burnout x Meeting Count (WP)",
    "nf_mean_within:meetings_count_within"      = "NF x Meeting Count (WP)",
    "burnout_mean_within:meetings_time_within"  = "Burnout x Meeting Duration (WP)",
    "nf_mean_within:meetings_time_within"       = "NF x Meeting Duration (WP)",
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
        LRT_str = paste0(
            formatC(LRT_chi2, digits = 2, format = "f"),
            " (df=", LRT_df, "), p ", fmt_p(LRT_p)
        )
    )

sep_row_mod <- tibble::tibble(Predictor = "Variance Components", M7a = "", M7b = "")
vc_block_mod <- dplyr::bind_rows(
    make_vc_row("tau_00 (L2 intercept var.)", "tau_00_str", vc_mod, model_short_mod),
    make_vc_row("sigma2 (L1 residual var.)", "sigma2_str", vc_mod, model_short_mod),
    make_vc_row("R2 marginal", "R2m_str", vc_mod, model_short_mod),
    make_vc_row("R2 conditional", "R2c_str", vc_mod, model_short_mod),
    make_vc_row("AIC", "AIC_str", vc_mod, model_short_mod),
    make_vc_row("LRT vs. base (chi2, df, p)", "LRT_str", vc_mod, model_short_mod)
)

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
        "* p < .05. ** p < .01. *** p < .001."
    ))

save_docx_table(
    ft4b,
    filepath  = file.path(TABLES_DIR, "table_04b_moderation.docx"),
    table_num = "4b",
    title     = "Moderation Models: Meeting Load x Burnout/NF Composites (M7a-M7b)"
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
        B = ifelse(is.na(Estimate) | hypothesis == "Prereq", "",
            formatC(Estimate, digits = 3, format = "f")
        ),
        p = ifelse(is.na(p_value), "", fmt_p(p_value)),
        beta = ifelse(is.na(beta), "", as.character(beta)),
        d = ifelse(is.na(pseudo_d), "", as.character(pseudo_d))
    ) |>
    dplyr::select(
        Hypothesis  = hypothesis,
        Description = description,
        Model       = model_name,
        B,
        beta,
        d,
        p,
        Supported
    )

ft5 <- apa_flextable(t5) |>
    add_apa_note(paste0(
        "B = unstandardized regression coefficient. beta = standardized coefficient ",
        "(parameters package). d = level-specific pseudo-d effect size (Lorah, 2018). ",
        "Hypothesis supported requires correct directional sign AND p < .05 ",
        "(one-tailed directional test). Moderation hypotheses (H3a/H3b) require p < .05 ",
        "(two-tailed). WP = within-person; BP = between-person. ",
        "* p < .05. ** p < .01. *** p < .001. ",
        "PC = Psychological Contract. NF = Need Frustration."
    ))

save_docx_table(
    ft5,
    filepath  = file.path(TABLES_DIR, "table_05_hypothesis_tests.docx"),
    table_num = 5,
    title     = "Summary of Hypothesis Tests"
)


log_msg("=== Publication tables complete. Output -> ", TABLES_DIR, " ===")
