#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# mlm_hypothesis_map.R — Manuscript-aligned hypothesis definitions
#
# Provides:
#   HYPOTHESIS_MAP         — single source of truth for all hypothesis labels,
#                            lme4 terms, directions, and model assignments,
#                            aligned to the dissertation proposal numbering.
#   get_coef_result()      — extract estimate/p/support from a fixed-effects tbl
#   evaluate_hypotheses()  — vectorized hypothesis evaluation returning a
#                            completed results tibble
#
# Numbering follows the dissertation proposal (proposal-final-draft.docx):
#   H1a  WP need frustration (NF) facets -> TI (+)                    [M3]
#   H1b  BP NF facet means -> TI (+)                                   [M4]
#   H2a  WP burnout facets -> TI (+)                                   [M3]
#   H2b  BP burnout facet means -> TI (+)                              [M4]
#   H3a  WP meeting load x NF composite -> TI (moderation)            [M7a/M7b]
#   H3b  WP meeting load x burnout composite -> TI (moderation)       [M7a/M7b]
#   H4a  BP PC breach -> TI (+)                                        [M5]
#   H4b  BP PC violation -> TI (+)                                     [M5]
#   H5   BP job satisfaction -> TI (-)                                 [M5]
#
# OPERATIONALIZATION NOTE — H3a/H3b (moderation):
#   The manuscript refers to "meeting load" as a single moderator.
#   It is operationalized here as two indicators (meeting count and meeting
#   minutes), yielding four interaction tests total (count x NF, mins x NF,
#   count x burnout, mins x burnout). This provides finer-grained insight into
#   whether frequency or duration of meetings drives the moderation effect.
#   Both indicators must be significant for full support of H3a or H3b.
#
# Dependencies: tibble, dplyr. common_utils.r (log_msg) must be sourced first.
# ---------------------------------------------------------------------------

library(tibble)
library(dplyr)


# ---------------------------------------------------------------------------
# [1] Hypothesis map
# ---------------------------------------------------------------------------

# One row per test (some hypotheses have one term; others have multiple facets
# or two operationalizations of meeting load).
#
# Columns:
#   hypothesis       — manuscript label (e.g., "H1a:comp")
#   description      — concise description of the test
#   level            — "L1 (within)" or "L2 (between)"
#   model_name       — exact string used as the 'model' column in fe_all
#   term             — exact lme4 fixed-effect term name
#   direction        — "+" (positive) or "-" (negative)
#   operationalization — brief note where relevant

HYPOTHESIS_MAP <- tibble::tibble(
    hypothesis = c(
        # Prerequisite
        "Prereq",
        # H1a: WP NF facets
        "H1a:comp", "H1a:auto", "H1a:relt",
        # H1b: BP NF facet means
        "H1b:comp", "H1b:auto", "H1b:relt",
        # H2a: WP burnout facets
        "H2a:pf", "H2a:cw", "H2a:ee",
        # H2b: BP burnout facet means
        "H2b:pf", "H2b:cw", "H2b:ee",
        # H3a: meeting load x NF (2 operationalizations)
        "H3a:count", "H3a:mins",
        # H3b: meeting load x burnout (2 operationalizations)
        "H3b:count", "H3b:mins",
        # H4a, H4b, H5
        "H4a", "H4b", "H5"
    ),
    description = c(
        "Between-person variance in TI (ICC > .05)",
        "WP competence frustration -> TI (+)",
        "WP autonomy frustration -> TI (+)",
        "WP relatedness frustration -> TI (+)",
        "BP competence frustration mean -> TI (+)",
        "BP autonomy frustration mean -> TI (+)",
        "BP relatedness frustration mean -> TI (+)",
        "WP physical fatigue -> TI (+)",
        "WP cognitive weariness -> TI (+)",
        "WP emotional exhaustion -> TI (+)",
        "BP physical fatigue mean -> TI (+)",
        "BP cognitive weariness mean -> TI (+)",
        "BP emotional exhaustion mean -> TI (+)",
        "WP meeting count x NF composite -> TI (+)",
        "WP meeting minutes x NF composite -> TI (+)",
        "WP meeting count x burnout composite -> TI (+)",
        "WP meeting minutes x burnout composite -> TI (+)",
        "BP PC breach -> TI (+)",
        "BP PC violation -> TI (+)",
        "BP job satisfaction -> TI (-)"
    ),
    level = c(
        "L2 (between)",
        "L1 (within)", "L1 (within)", "L1 (within)",
        "L2 (between)", "L2 (between)", "L2 (between)",
        "L1 (within)", "L1 (within)", "L1 (within)",
        "L2 (between)", "L2 (between)", "L2 (between)",
        "L1 (within)", "L1 (within)",
        "L1 (within)", "L1 (within)",
        "L2 (between)", "L2 (between)", "L2 (between)"
    ),
    model_name = c(
        "Model 0: Unconditional Means",
        "Model 3: L1 Within-Person", "Model 3: L1 Within-Person", "Model 3: L1 Within-Person",
        "Model 4: L1 Within + Between", "Model 4: L1 Within + Between", "Model 4: L1 Within + Between",
        "Model 3: L1 Within-Person", "Model 3: L1 Within-Person", "Model 3: L1 Within-Person",
        "Model 4: L1 Within + Between", "Model 4: L1 Within + Between", "Model 4: L1 Within + Between",
        "Model 7a: Count x Composites", "Model 7b: Minutes x Composites",
        "Model 7a: Count x Composites", "Model 7b: Minutes x Composites",
        "Model 5: L1 + L2 Study Variables",
        "Model 5: L1 + L2 Study Variables",
        "Model 5: L1 + L2 Study Variables"
    ),
    term = c(
        NA_character_,
        "comp_mean_within", "auto_mean_within", "relt_mean_within",
        "comp_mean_between", "auto_mean_between", "relt_mean_between",
        "pf_mean_within", "cw_mean_within", "ee_mean_within",
        "pf_mean_between", "cw_mean_between", "ee_mean_between",
        "nf_mean_within:meetings_count_within",
        "nf_mean_within:meetings_mins_within",
        "burnout_mean_within:meetings_count_within",
        "burnout_mean_within:meetings_mins_within",
        "br_mean_c", "vio_mean_c", "js_mean_c"
    ),
    direction = c(
        NA_character_,
        "+", "+", "+",
        "+", "+", "+",
        "+", "+", "+",
        "+", "+", "+",
        "+", "+",
        "+", "+",
        "+", "+", "-"
    )
)


# ---------------------------------------------------------------------------
# [2] Helper: extract one coefficient result
# ---------------------------------------------------------------------------

#' Extract estimate, p-value, and support verdict from a fixed-effects tibble
#'
#' @param fe_tbl    Data frame with columns model, term, estimate, p.value
#'                  (as returned by broom.mixed::tidy() bound with a model column)
#' @param model_nm  Character; exact model name to filter
#' @param term_nm   Character; exact term name to filter
#' @param direction Character; "+" or "-"
#' @return Named list: $est (numeric), $p (numeric), $supported (logical)
#'
get_coef_result <- function(fe_tbl, model_nm, term_nm, direction) {
    row <- fe_tbl |>
        dplyr::filter(model == model_nm, term == term_nm)

    if (nrow(row) == 0) {
        return(list(est = NA_real_, p = NA_real_, supported = NA))
    }

    est   <- row$estimate[1]
    p_val <- row$p.value[1]
    dir_ok <- if (direction == "+") est > 0 else est < 0
    list(
        est       = round(est, 4),
        p         = p_val,
        supported = dir_ok & !is.na(p_val) & p_val < 0.05
    )
}


# ---------------------------------------------------------------------------
# [3] Vectorized hypothesis evaluation
# ---------------------------------------------------------------------------

#' Populate hypothesis test results from a combined fixed-effects table
#'
#' Matches each row in hyp_map to the corresponding fixed-effect term in
#' fe_all and returns a completed tibble with Estimate, p_value, and Supported.
#' The ICC prerequisite row is handled via the separately passed icc_value.
#'
#' @param fe_all    Data frame; combined broom.mixed::tidy() output with a
#'                  'model' column (one row per term per model).
#' @param hyp_map   Data frame; HYPOTHESIS_MAP or a subset of it.
#' @param icc_value Numeric; ICC_adjusted from the null model (for Prereq row).
#' @return Tibble: hyp_map columns + Estimate, p_value, Supported.
#'
evaluate_hypotheses <- function(fe_all, hyp_map, icc_value) {
    results <- hyp_map |>
        dplyr::mutate(
            Estimate  = NA_real_,
            p_value   = NA_real_,
            Supported = NA_character_
        )

    for (i in seq_len(nrow(results))) {
        hyp <- results$hypothesis[i]
        trm <- results$term[i]
        mdl <- results$model_name[i]
        dir <- results$direction[i]

        # Prerequisite row uses ICC, not a model coefficient
        if (hyp == "Prereq") {
            results$Estimate[i]  <- round(icc_value, 4)
            results$p_value[i]   <- NA_real_
            results$Supported[i] <- ifelse(icc_value > 0.05, "Yes", "No")
            next
        }

        if (is.na(trm) || is.na(mdl) || is.na(dir)) next

        r <- get_coef_result(fe_all, mdl, trm, dir)
        results$Estimate[i]  <- r$est
        results$p_value[i]   <- round(r$p, 4)
        results$Supported[i] <- ifelse(isTRUE(r$supported), "Yes", "No")
    }

    results
}
