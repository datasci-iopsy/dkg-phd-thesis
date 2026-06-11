#!/usr/bin/env Rscript
# =============================================================================
# analysis/tests/test_correlation_outputs.r
#
# Integration test for correlation.r output contract: every correlation
# matrix CSV must ship a companion p-value matrix so downstream tables can
# attach significance stars, and a true between-person matrix (Pearson on
# person means) must exist covering both L1 and L2 variables.
#
# Run after the study pipeline: uvr run analysis/tests/test_correlation_outputs.r
# Skips (does not fail) when pipeline outputs are absent (e.g. fresh clone).
# =============================================================================

library(testthat)
library(here)

FIGS_DIR <- here::here("analysis", "run_study_analysis", "figs", "corr")
EXPORT_CSV <- here::here(
    "analysis", "run_study_analysis", "data", "export",
    "qualtrics_fct_panel_responses_cleaned.csv"
)

read_matrix_csv <- function(filename) {
    path <- file.path(FIGS_DIR, filename)
    if (!file.exists(path)) {
        return(NULL)
    }
    df <- read.csv(path, row.names = 1, check.names = FALSE)
    as.matrix(df)
}

pairs <- list(
    c("corr_01_l2_pearson_matrix.csv", "corr_01_l2_pearson_pvalues.csv"),
    c("corr_02_l1_pooled_pearson_matrix.csv", "corr_02_l1_pooled_pearson_pvalues.csv"),
    c("corr_03_mlm_within_partial_matrix.csv", "corr_03_mlm_within_partial_pvalues.csv"),
    c("corr_04_rmcorr_within_matrix.csv", "corr_04_rmcorr_within_pvalues.csv"),
    c("corr_05_between_person_matrix.csv", "corr_05_between_person_pvalues.csv")
)

test_that("every correlation matrix has an aligned companion p-value matrix", {
    skip_if_not(
        file.exists(file.path(FIGS_DIR, "corr_01_l2_pearson_matrix.csv")),
        "correlation.r outputs not present; run make study_analysis first"
    )
    for (pair in pairs) {
        r_mat <- read_matrix_csv(pair[1])
        p_mat <- read_matrix_csv(pair[2])
        expect_false(is.null(r_mat), info = paste(pair[1], "missing"))
        expect_false(is.null(p_mat), info = paste(pair[2], "missing"))
        # Alignment: a p matrix with different row/col order would star the
        # wrong cells downstream
        expect_identical(dimnames(r_mat), dimnames(p_mat), info = pair[2])
        # p must be probabilities, not correlations accidentally re-written:
        # r matrices contain negatives; p matrices must not
        off_diag <- p_mat[upper.tri(p_mat) | lower.tri(p_mat)]
        expect_true(
            all(is.na(off_diag) | (off_diag >= 0 & off_diag <= 1)),
            info = paste(pair[2], "has values outside [0, 1]")
        )
        expect_false(
            isTRUE(all.equal(r_mat, p_mat)),
            info = paste(pair[2], "is identical to its r matrix")
        )
    }
})

test_that("between-person matrix covers person-mean L1 vars and L2 vars", {
    bw <- read_matrix_csv("corr_05_between_person_matrix.csv")
    skip_if_not(!is.null(bw), "corr_05 not present")
    # The combined Table 2 needs both blocks in one person-level matrix;
    # corr_01 (L2-only) cannot fill the L1 x L2 quadrant
    expect_true(all(c("pf_mean", "turnover_intention_mean") %in% rownames(bw)))
    expect_true(all(c("pa_mean", "js_mean") %in% rownames(bw)))
})

test_that("corr_05 r and p match cor.test on person means from cleaned data", {
    bw <- read_matrix_csv("corr_05_between_person_matrix.csv")
    bw_p <- read_matrix_csv("corr_05_between_person_pvalues.csv")
    skip_if_not(
        !is.null(bw) && !is.null(bw_p) && file.exists(EXPORT_CSV),
        "corr_05 outputs or cleaned export not present"
    )
    panel <- read.csv(EXPORT_CSV)
    means <- aggregate(
        panel[, c("pf_mean", "turnover_intention_mean")],
        by = list(response_id = panel$response_id),
        FUN = mean, na.rm = TRUE
    )
    ct <- cor.test(means$pf_mean, means$turnover_intention_mean)
    expect_equal(
        bw["pf_mean", "turnover_intention_mean"],
        unname(ct$estimate),
        tolerance = 1e-6
    )
    expect_equal(
        bw_p["pf_mean", "turnover_intention_mean"],
        ct$p.value,
        tolerance = 1e-6
    )
})

log_note <- function(...) cat("[test_correlation_outputs]", ..., "\n")
log_note("complete")
