#!/usr/bin/env Rscript
# =============================================================================
# analysis/run_synthetic_data/scripts/r/multilevel_model.R
#
# Comprehensive Multilevel Model Building Sequence for Turnover Intentions
#
# Design : ~800 participants (L2) x 3 within-day timepoints (L1)
# DV     : turnover_intention_mean (1-5 ordinal, treated as continuous)
# Method : Systematic model building following Hox et al. (2018) & Singer &
#          Willett (2003). Models 0-6 are fit sequentially, each adding a
#          layer of complexity justified by likelihood ratio tests.
# Output : CSVs + PDFs -> analysis/run_synthetic_data/figs/mlm/
#
# Centering: Enders & Tofighi (2007) / Curran & Bauer (2011) decomposition
#   - L1 predictors: person-mean centered (within) + grand-mean centered
#     person means (between) via datawizard::demean()
#   - L2 predictors: grand-mean centered
#
# Estimation:
#   - ML  for likelihood ratio tests (LRTs comparing fixed effects)
#   - REML for final parameter reporting (less biased variance estimates)
# =============================================================================

# --- [0] Libraries and setup -------------------------------------------------
library(lme4)
library(lmerTest)
library(broom.mixed)
library(performance)
library(parameters)
library(effectsize)
library(datawizard)
library(car)
library(ggplot2)
library(patchwork)
library(gridExtra)
library(dplyr)
library(tidyr)
library(purrr)
library(readr)
library(tibble)
library(stringr)
library(forcats)
library(here)
library(glue)

options(tibble.width = Inf)
here::here()

# Source shared utilities (log_msg, ensure_dir)
source(here::here("analysis", "shared", "utils", "common_utils.r"))

# --- Global settings ----------------------------------------------------------
FIGS_DIR <- here::here("analysis", "run_synthetic_data", "figs", "mlm")
ensure_dir(FIGS_DIR)

# APA-like ggplot2 theme
theme_apa <- theme_minimal(base_size = 12, base_family = "serif") +
    theme(
        panel.grid.minor = element_blank(),
        panel.grid.major = element_line(color = "grey92"),
        axis.line        = element_line(color = "black", linewidth = 0.4),
        axis.ticks       = element_line(color = "black", linewidth = 0.3),
        strip.text       = element_text(face = "bold", size = 11),
        plot.title       = element_text(face = "bold", size = 13, hjust = 0),
        plot.subtitle    = element_text(size = 10, hjust = 0, color = "grey30"),
        legend.position  = "bottom",
        legend.title     = element_text(face = "bold", size = 10),
        plot.margin      = margin(10, 15, 10, 15)
    )
theme_set(theme_apa)

# PDF save helper
save_pdf <- function(plot, filename, width = 10, height = 7) {
    filepath <- file.path(FIGS_DIR, filename)
    ggsave(filepath,
        plot = plot, device = "pdf",
        width = width, height = height, dpi = 300
    )
    log_msg("Saved: ", filepath)
}

# Default optimizer control for lmer
CTRL <- lmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 200000))

log_msg("=== MULTILEVEL MODEL BUILDING SEQUENCE ===")
log_msg("Output directory: ", FIGS_DIR)


# =============================================================================
# [1] DATA LOADING
# =============================================================================
log_msg("=== [1] Loading data ===")

df_raw <- readr::read_csv(
    here::here(
        "analysis", "run_synthetic_data", "data", "export",
        "syn_qualtrics_fct_panel_responses_20260308.csv"
    ),
    show_col_types = FALSE
)
log_msg("Loaded: ", nrow(df_raw), " rows x ", ncol(df_raw), " columns")

n_participants <- dplyr::n_distinct(df_raw$response_id)
log_msg("Participants (L2): ", n_participants)
log_msg("Timepoints  (L1) : ", max(df_raw$timepoint))

# Variable name vectors
l1_predictor_vars <- c(
    "pf_mean", "cw_mean", "ee_mean",
    "comp_mean", "auto_mean", "relt_mean",
    "meetings_count", "meetings_mins"
)
l1_marker_var <- "atcb_mean"
l1_all_center <- c(l1_predictor_vars, l1_marker_var)

l2_study_vars <- c("pa_mean", "na_mean", "br_mean", "vio_mean", "js_mean")
l2_demo_vars <- c("age", "gender", "job_tenure", "is_remote")

dv <- "turnover_intention_mean"

# Pretty labels for output tables
var_labels <- c(
    pf_mean = "Physical Fatigue", cw_mean = "Cognitive Weariness",
    ee_mean = "Emotional Exhaustion", comp_mean = "NF: Competence",
    auto_mean = "NF: Autonomy", relt_mean = "NF: Relatedness",
    atcb_mean = "ATCB (Marker)",
    meetings_count = "Meeting Count", meetings_mins = "Meeting Minutes",
    pa_mean = "Positive Affect", na_mean = "Negative Affect",
    br_mean = "PC Breach", vio_mean = "PC Violation",
    js_mean = "Job Satisfaction",
    turnover_intention_mean = "Turnover Intention"
)


# =============================================================================
# [2] CENTERING AND VARIABLE PREPARATION
# =============================================================================
log_msg("=== [2] Centering and variable preparation ===")

# 2a. Time centering: 0, 1, 2 (intercept = first timepoint)
df <- df_raw |>
    dplyr::mutate(time_c = timepoint - 1)

# 2b. L1 predictor centering: WP/BP decomposition via datawizard::demean()
#     Creates {var}_within (person-mean centered) and {var}_between
#     (grand-mean centered person mean) for each variable.
log_msg("  Applying person-mean centering (CWC) for L1 predictors...")
df <- datawizard::demean(
    df,
    select = l1_all_center,
    by = "response_id"
)

# Verify centering worked: within-person means should be ~0 per person
wp_check <- df |>
    dplyr::group_by(response_id) |>
    dplyr::summarise(
        across(ends_with("_within"), ~ mean(., na.rm = TRUE)),
        .groups = "drop"
    ) |>
    dplyr::summarise(
        across(ends_with("_within"), ~ max(abs(.), na.rm = TRUE))
    )
log_msg(
    "  Max within-person mean deviation: ",
    round(max(as.numeric(wp_check[1, ])), 8),
    " (should be ~0)"
)

# 2c. L2 study variables: grand-mean center
for (v in l2_study_vars) {
    new_name <- paste0(v, "_c")
    df[[new_name]] <- df[[v]] - mean(df[[v]], na.rm = TRUE)
}

# 2d. Demographics: center age, factor-code categoricals
df <- df |>
    dplyr::mutate(
        age_c      = age - mean(age, na.rm = TRUE),
        gender     = factor(gender),
        job_tenure = factor(job_tenure),
        is_remote  = as.integer(is_remote)
    )

log_msg("  Centering complete. Total columns: ", ncol(df))


# =============================================================================
# [3] HELPER FUNCTIONS
# =============================================================================
log_msg("=== [3] Defining helper functions ===")

#' Fit lmer with optimizer fallback and singularity check
safe_lmer <- function(formula, data, REML = TRUE, ctrl = CTRL) {
    fit <- tryCatch(
        lmerTest::lmer(formula, data = data, REML = REML, control = ctrl),
        error = function(e) {
            log_msg("  [WARN] bobyqa failed: ", conditionMessage(e))
            log_msg("  [WARN] Retrying with nloptwrap/nlminb...")
            ctrl2 <- lmerControl(
                optimizer = "nloptwrap",
                optCtrl = list(method = "nlminb", maxfun = 200000)
            )
            tryCatch(
                lmerTest::lmer(formula, data = data, REML = REML, control = ctrl2),
                error = function(e2) {
                    log_msg(
                        "  [ERROR] Both optimizers failed: ",
                        conditionMessage(e2)
                    )
                    return(NULL)
                }
            )
        }
    )

    if (!is.null(fit) && isSingular(fit)) {
        log_msg("  [WARN] Singular fit detected (near-zero variance component)")
    }

    return(fit)
}


#' Extract a standardized summary tibble from a fitted lmer model
extract_model_summary <- function(fit, model_name) {
    if (is.null(fit)) {
        return(tibble::tibble(model = model_name, note = "Model failed to converge"))
    }

    # Fixed effects
    fe <- broom.mixed::tidy(fit,
        effects = "fixed", conf.int = TRUE,
        conf.level = 0.95
    ) |>
        dplyr::mutate(model = model_name)

    # Random effects
    re <- broom.mixed::tidy(fit, effects = "ran_pars") |>
        dplyr::mutate(model = model_name)

    # Fit statistics
    gl <- broom.mixed::glance(fit) |>
        dplyr::mutate(model = model_name)

    # Pseudo R-squared (Nakagawa & Schielzeth)
    r2 <- tryCatch(
        {
            r2_vals <- performance::r2_nakagawa(fit)
            tibble::tibble(
                model = model_name,
                R2_marginal = r2_vals$R2_marginal,
                R2_conditional = r2_vals$R2_conditional
            )
        },
        error = function(e) {
            tibble::tibble(
                model = model_name,
                R2_marginal = NA_real_,
                R2_conditional = NA_real_
            )
        }
    )

    list(fixed = fe, random = re, fit = gl, r2 = r2)
}


#' Likelihood ratio test between two ML-fitted models
compare_models <- function(fit_a, fit_b, name_a, name_b) {
    if (is.null(fit_a) || is.null(fit_b)) {
        return(tibble::tibble(
            comparison = paste(name_b, "vs", name_a),
            note = "One or both models failed"
        ))
    }
    a <- anova(fit_a, fit_b)
    tibble::tibble(
        comparison = paste(name_b, "vs", name_a),
        chi_sq     = a[["Chisq"]][2],
        df         = a[["Df"]][2],
        p_value    = a[["Pr(>Chisq)"]][2]
    )
}


#' Generate 4-panel residual diagnostic PDF
check_assumptions <- function(fit, model_name) {
    if (is.null(fit)) {
        return(invisible(NULL))
    }

    resids <- residuals(fit)
    fitted_vals <- fitted(fit)
    re <- ranef(fit)$response_id

    # Panel 1: L1 residual QQ
    p1 <- ggplot(data.frame(r = resids), aes(sample = r)) +
        stat_qq(alpha = 0.3, size = 0.8) +
        stat_qq_line(color = "red") +
        labs(title = "L1 Residual QQ Plot", x = "Theoretical", y = "Sample")

    # Panel 2: Residuals vs fitted
    p2 <- ggplot(
        data.frame(fitted = fitted_vals, resid = resids),
        aes(x = fitted, y = resid)
    ) +
        geom_point(alpha = 0.2, size = 0.8) +
        geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
        geom_smooth(
            method = "loess", se = FALSE, color = "blue",
            linewidth = 0.6
        ) +
        labs(title = "Residuals vs. Fitted", x = "Fitted", y = "Residual")

    # Panel 3: Random intercept QQ
    p3 <- ggplot(data.frame(ri = re[["(Intercept)"]]), aes(sample = ri)) +
        stat_qq(alpha = 0.5, size = 0.8) +
        stat_qq_line(color = "red") +
        labs(
            title = "Random Intercept QQ Plot",
            x = "Theoretical", y = "Sample"
        )

    # Panel 4: Scale-location
    p4 <- ggplot(
        data.frame(
            fitted = fitted_vals,
            sqrt_abs_resid = sqrt(abs(resids))
        ),
        aes(x = fitted, y = sqrt_abs_resid)
    ) +
        geom_point(alpha = 0.2, size = 0.8) +
        geom_smooth(
            method = "loess", se = FALSE, color = "blue",
            linewidth = 0.6
        ) +
        labs(
            title = "Scale-Location",
            x = "Fitted", y = expression(sqrt("|Residual|"))
        )

    combined <- (p1 | p2) / (p3 | p4) +
        patchwork::plot_annotation(
            title = paste("Model Diagnostics:", model_name),
            theme = theme(plot.title = element_text(face = "bold", size = 14))
        )

    filename <- paste0(
        "mlm_diag_",
        tolower(gsub(" ", "_", model_name)), ".pdf"
    )
    save_pdf(combined, filename, width = 12, height = 9)
}


#' Check multicollinearity and return VIF tibble
check_vif <- function(fit, model_name) {
    if (is.null(fit)) {
        return(tibble::tibble())
    }

    vif_result <- tryCatch(
        performance::check_collinearity(fit),
        error = function(e) {
            log_msg(
                "  [WARN] VIF check failed for ", model_name, ": ",
                conditionMessage(e)
            )
            return(NULL)
        }
    )

    if (is.null(vif_result)) {
        return(tibble::tibble())
    }

    vif_tbl <- as.data.frame(vif_result) |>
        tibble::as_tibble() |>
        dplyr::mutate(model = model_name)

    # Flag high VIF
    high_vif <- vif_tbl |> dplyr::filter(VIF > 5)
    if (nrow(high_vif) > 0) {
        log_msg("  [WARN] High VIF (>5) in ", model_name, ":")
        for (i in seq_len(nrow(high_vif))) {
            log_msg(
                "    ", high_vif$Term[i], ": VIF = ",
                round(high_vif$VIF[i], 2)
            )
        }
    }

    return(vif_tbl)
}


#' Save a VIF bar chart as PDF
save_vif_plot <- function(vif_tbl, model_name) {
    if (nrow(vif_tbl) == 0) {
        return(invisible(NULL))
    }

    p <- vif_tbl |>
        dplyr::mutate(
            Term = forcats::fct_reorder(Term, VIF),
            flag = ifelse(VIF > 5, "High (>5)", "Acceptable")
        ) |>
        ggplot(aes(x = Term, y = VIF, fill = flag)) +
        geom_col() +
        geom_hline(yintercept = 5, linetype = "dashed", color = "orange") +
        geom_hline(yintercept = 10, linetype = "dashed", color = "red") +
        coord_flip() +
        scale_fill_manual(values = c(
            "Acceptable" = "steelblue",
            "High (>5)" = "tomato"
        )) +
        labs(
            title = paste("Variance Inflation Factors:", model_name),
            x = NULL, y = "VIF", fill = NULL
        )

    filename <- paste0(
        "mlm_vif_",
        tolower(gsub(" ", "_", model_name)), ".pdf"
    )
    save_pdf(p, filename, width = 10, height = max(6, nrow(vif_tbl) * 0.35))
}


#' Standardized coefficients via effectsize (method = "basic")
#'
#' The "basic" method post-hoc divides each coefficient by (SD_x / SD_y).
#' Unlike "refit" (which re-fits on z-scored data and can fail with complex
#' random structures), "basic" is algebraically equivalent for continuous
#' predictors and far more stable.
compute_standardized_coefs <- function(fit, model_name) {
    if (is.null(fit)) {
        return(tibble::tibble(model = model_name, note = "Model is NULL"))
    }
    tryCatch(
        {
            std <- effectsize::standardize_parameters(fit,
                method = "basic",
                ci = 0.95
            )
            std |>
                as.data.frame() |>
                tibble::as_tibble() |>
                dplyr::mutate(model = model_name)
        },
        error = function(e) {
            log_msg(
                "  [WARN] Standardization failed for ", model_name, ": ",
                conditionMessage(e)
            )
            tibble::tibble(model = model_name, note = conditionMessage(e))
        }
    )
}


#' Level-specific pseudo-d effect sizes for MLM fixed effects
#'
#' For each fixed effect, divides the unstandardized coefficient by the
#' level-appropriate SD of the DV:
#'   - L1 within-person terms  -> sigma  (within-person SD of DV)
#'   - L2 between-person terms -> sqrt(tau_00)  (between-person SD of DV)
#'   - Intercept / time        -> total SD as reference
#'
#' This is consistent with Arend & Schafer (2019) parameterisation used in
#' the power analysis and is recommended by Lorah (2018) for MLM.
compute_level_specific_es <- function(fit, model_name) {
    if (is.null(fit)) {
        return(tibble::tibble(model = model_name, note = "Model is NULL"))
    }

    # Extract variance components
    vc <- as.data.frame(VarCorr(fit))
    sigma_val <- sqrt(vc$vcov[vc$grp == "Residual"])
    tau_00_row <- vc$vcov[vc$grp == "response_id" &
        vc$var1 == "(Intercept)" & is.na(vc$var2)]
    tau_00_sd <- if (length(tau_00_row) > 0) sqrt(tau_00_row) else NA_real_

    # Extract fixed effects with CIs
    fe <- broom.mixed::tidy(fit,
        effects = "fixed", conf.int = TRUE,
        conf.level = 0.95
    )

    # Classify each term by level and compute pseudo-d
    fe |>
        dplyr::mutate(
            level = dplyr::case_when(
                term == "(Intercept)" ~ "intercept",
                term == "time_c"     ~ "time",
                stringr::str_ends(term, "_within") ~ "L1 (within)",
                stringr::str_ends(term, "_between") ~ "L2 (between)",
                # L2 study/demo variables (centered with _c suffix or factor)
                TRUE ~ "L2 (between)"
            ),
            sd_dv = dplyr::case_when(
                level == "L1 (within)"  ~ sigma_val,
                level == "L2 (between)" ~ tau_00_sd,
                # intercept/time: use total SD for reference
                TRUE ~ sqrt(sigma_val^2 + tau_00_sd^2)
            ),
            pseudo_d      = estimate / sd_dv,
            pseudo_d_lo   = conf.low / sd_dv,
            pseudo_d_hi   = conf.high / sd_dv,
            magnitude = dplyr::case_when(
                is.na(pseudo_d)      ~ NA_character_,
                abs(pseudo_d) < 0.20 ~ "negligible",
                abs(pseudo_d) < 0.50 ~ "small",
                abs(pseudo_d) < 0.80 ~ "medium",
                TRUE                 ~ "large"
            ),
            model = model_name
        ) |>
        dplyr::select(
            model, term, level, estimate, std.error,
            pseudo_d, pseudo_d_lo, pseudo_d_hi, sd_dv, magnitude
        )
}


#' Delta-R² and Cohen's f² between sequential models
#'
#' f² = delta_R2 / (1 - R2_full) where R2_full is the final model's R².
#' Benchmarks: .02 = small, .15 = medium, .35 = large (Cohen 1988).
compute_delta_r2 <- function(comparison_tbl) {
    r2_full <- as.numeric(max(comparison_tbl$R2_marginal, na.rm = TRUE))
    denom <- if (r2_full < 1) (1 - r2_full) else NA_real_

    comparison_tbl |>
        dplyr::arrange(match(
            Model,
            comparison_tbl$Model
        )) |>
        dplyr::mutate(
            delta_R2_marginal = R2_marginal - dplyr::lag(R2_marginal, default = 0),
            delta_R2_conditional = R2_conditional -
                dplyr::lag(R2_conditional, default = 0),
            f2 = delta_R2_marginal / denom,
            f2_magnitude = dplyr::case_when(
                is.na(f2)   ~ NA_character_,
                f2 < 0.02   ~ "negligible",
                f2 < 0.15   ~ "small",
                f2 < 0.35   ~ "medium",
                TRUE         ~ "large"
            )
        ) |>
        dplyr::select(
            Model, R2_marginal, R2_conditional,
            delta_R2_marginal, delta_R2_conditional,
            f2, f2_magnitude
        )
}


# =============================================================================
# [4] MODEL 0: UNCONDITIONAL MEANS (EMPTY/NULL)
# =============================================================================
log_msg("=== [4] Model 0: Unconditional Means ===")
log_msg("  Tests H1: Significant between-person variance in TI")
log_msg("  Formula: TI ~ 1 + (1 | response_id)")

m0_reml <- safe_lmer(turnover_intention_mean ~ 1 + (1 | response_id),
    data = df, REML = TRUE
)
m0_ml <- safe_lmer(turnover_intention_mean ~ 1 + (1 | response_id),
    data = df, REML = FALSE
)

# ICC
icc_m0 <- performance::icc(m0_reml)
log_msg("  ICC (adjusted)  = ", round(icc_m0$ICC_adjusted, 4))
log_msg("  ICC (conditional) = ", round(icc_m0$ICC_conditional, 4))

# Variance components
vc_m0 <- as.data.frame(VarCorr(m0_reml))
tau_00 <- vc_m0$vcov[vc_m0$grp == "response_id"]
sigma2 <- vc_m0$vcov[vc_m0$grp == "Residual"]
log_msg("  tau_00 (between) = ", round(tau_00, 4))
log_msg("  sigma2 (within)  = ", round(sigma2, 4))
log_msg("  Grand mean TI    = ", round(fixef(m0_reml)[1], 4))
log_msg(
    "  H1 result: ICC = ", round(icc_m0$ICC_adjusted, 4),
    " -> ", ifelse(icc_m0$ICC_adjusted > 0.05, "SUPPORTED", "NOT SUPPORTED"),
    " (>0.05 threshold for MLM)"
)

m0_summary <- extract_model_summary(m0_reml, "Model 0: Unconditional Means")


# =============================================================================
# [5] MODEL 1: UNCONDITIONAL GROWTH - FIXED TIME
# =============================================================================
log_msg("=== [5] Model 1: Unconditional Growth (Fixed Slope) ===")
log_msg("  Tests H2a: Positive linear trend in TI across workday")
log_msg("  Formula: TI ~ time_c + (1 | response_id)")

m1_reml <- safe_lmer(turnover_intention_mean ~ time_c + (1 | response_id),
    data = df, REML = TRUE
)
m1_ml <- safe_lmer(turnover_intention_mean ~ time_c + (1 | response_id),
    data = df, REML = FALSE
)

# LRT: Model 1 vs Model 0
lrt_1v0 <- compare_models(m0_ml, m1_ml, "Model 0", "Model 1")
log_msg(
    "  LRT Model 1 vs 0: chi2 = ", round(lrt_1v0$chi_sq, 3),
    ", df = ", lrt_1v0$df, ", p = ", format.pval(lrt_1v0$p_value, digits = 4)
)

time_coef <- fixef(m1_reml)["time_c"]
log_msg("  time_c coefficient = ", round(time_coef, 4))
log_msg(
    "  H2a result: time_c = ", round(time_coef, 4),
    " -> ", ifelse(time_coef > 0 && lrt_1v0$p_value < 0.05,
        "SUPPORTED (positive trend)",
        "NOT SUPPORTED"
    )
)

m1_summary <- extract_model_summary(m1_reml, "Model 1: Fixed Time")


# =============================================================================
# [6] MODEL 2: UNCONDITIONAL GROWTH - RANDOM SLOPE
# =============================================================================
log_msg("=== [6] Model 2: Unconditional Growth (Random Slope) ===")
log_msg("  Tests H2b: Significant random slope variance")
log_msg("  Tests H2c: Random slopes model fits better than fixed slopes")
log_msg("  Formula: TI ~ time_c + (time_c | response_id)")

# Try full random slope (correlated)
m2_reml <- safe_lmer(
    turnover_intention_mean ~ time_c + (time_c | response_id),
    data = df, REML = TRUE
)
m2_ml <- safe_lmer(
    turnover_intention_mean ~ time_c + (time_c | response_id),
    data = df, REML = FALSE
)

# Fallback: uncorrelated random effects if full model is singular or failed
use_random_slope <- TRUE
re_note <- "correlated"

if (is.null(m2_reml) || isSingular(m2_reml)) {
    log_msg(
        "  [INFO] Full random slope model singular/failed. ",
        "Trying uncorrelated (time_c || response_id)..."
    )
    m2_reml <- safe_lmer(
        turnover_intention_mean ~ time_c + (time_c || response_id),
        data = df, REML = TRUE
    )
    m2_ml <- safe_lmer(
        turnover_intention_mean ~ time_c + (time_c || response_id),
        data = df, REML = FALSE
    )
    re_note <- "uncorrelated"
}

if (is.null(m2_reml) || isSingular(m2_reml)) {
    log_msg("  [INFO] Random slope not supported with 3 timepoints.")
    log_msg("  [INFO] Proceeding with random intercept only for all models.")
    use_random_slope <- FALSE
    re_note <- "intercept only"
    # Reuse Model 1 as Model 2
    m2_reml <- m1_reml
    m2_ml <- m1_ml
}

if (use_random_slope) {
    lrt_2v1 <- compare_models(m1_ml, m2_ml, "Model 1", "Model 2")
    log_msg(
        "  LRT Model 2 vs 1: chi2 = ", round(lrt_2v1$chi_sq, 3),
        ", df = ", lrt_2v1$df,
        ", p = ", format.pval(lrt_2v1$p_value, digits = 4)
    )

    # Extract random slope variance
    vc_m2 <- as.data.frame(VarCorr(m2_reml))
    tau_11_row <- vc_m2[vc_m2$grp == "response_id" &
        vc_m2$var1 == "time_c" & is.na(vc_m2$var2), ]
    tau_11 <- if (nrow(tau_11_row) > 0) tau_11_row$vcov[1] else NA

    log_msg(
        "  Random slope variance (tau_11) = ",
        ifelse(is.na(tau_11), "NA", round(tau_11, 4))
    )
    log_msg("  Random effects structure: ", re_note)

    # Re-evaluate: if LRT is not significant, drop random slope
    if (!is.na(lrt_2v1$p_value) && lrt_2v1$p_value >= 0.05) {
        log_msg("  [INFO] Random slope LRT not significant (p >= .05).")
        log_msg("  [INFO] Retaining random intercept only for parsimony.")
        use_random_slope <- FALSE
        re_note <- "intercept only (LRT ns)"
    }

    log_msg(
        "  H2b result: tau_11 = ",
        ifelse(is.na(tau_11), "NA", round(tau_11, 4)),
        " -> ", ifelse(!is.na(tau_11) && tau_11 > 0 && lrt_2v1$p_value < 0.05,
            "SUPPORTED", "NOT SUPPORTED"
        )
    )
    log_msg(
        "  H2c result: LRT p = ",
        format.pval(lrt_2v1$p_value, digits = 4),
        " -> ", ifelse(lrt_2v1$p_value < 0.05, "SUPPORTED", "NOT SUPPORTED")
    )
} else {
    lrt_2v1 <- tibble::tibble(
        comparison = "Model 2 vs Model 1",
        chi_sq = NA_real_, df = NA_integer_, p_value = NA_real_
    )
    log_msg("  H2b result: NOT SUPPORTED (random slope not estimable)")
    log_msg("  H2c result: NOT SUPPORTED (random slope not estimable)")
}

m2_summary <- extract_model_summary(m2_reml, "Model 2: Random Slope")
log_msg(
    "  Decision: use_random_slope = ", use_random_slope,
    " (", re_note, ")"
)


# =============================================================================
# [7] MODEL 3: WITHIN-PERSON (L1) PREDICTORS
# =============================================================================
log_msg("=== [7] Model 3: Within-Person (L1) Predictors ===")
log_msg("  Tests H3a-h: Burnout, NF, meetings -> TI (within-person)")

# Build formula dynamically based on random slope decision
re_term <- if (use_random_slope) "(time_c | response_id)" else "(1 | response_id)"

m3_formula <- as.formula(paste(
    "turnover_intention_mean ~ time_c +",
    "pf_mean_within + cw_mean_within + ee_mean_within +",
    "comp_mean_within + auto_mean_within + relt_mean_within +",
    "meetings_count_within + meetings_mins_within +",
    "atcb_mean_within +",
    re_term
))
log_msg("  Formula: ", deparse(m3_formula, width.cutoff = 200))

m3_reml <- safe_lmer(m3_formula, data = df, REML = TRUE)
m3_ml <- safe_lmer(m3_formula, data = df, REML = FALSE)

# LRT: Model 3 vs best unconditional
m_prev_ml <- if (use_random_slope) m2_ml else m1_ml
prev_name <- if (use_random_slope) "Model 2" else "Model 1"
lrt_3vp <- compare_models(m_prev_ml, m3_ml, prev_name, "Model 3")
log_msg(
    "  LRT Model 3 vs ", prev_name, ": chi2 = ",
    round(lrt_3vp$chi_sq, 3),
    ", df = ", lrt_3vp$df, ", p = ", format.pval(lrt_3vp$p_value, digits = 4)
)

# Hypothesis tests for H3a-h
fe3 <- broom.mixed::tidy(m3_reml, effects = "fixed", conf.int = TRUE)
h3_vars <- c(
    "pf_mean_within", "cw_mean_within", "ee_mean_within",
    "comp_mean_within", "auto_mean_within", "relt_mean_within",
    "meetings_count_within", "meetings_mins_within"
)
h3_labels <- c("H3a", "H3b", "H3c", "H3d", "H3e", "H3f", "H3g", "H3h")
for (i in seq_along(h3_vars)) {
    row <- fe3[fe3$term == h3_vars[i], ]
    if (nrow(row) > 0) {
        log_msg(
            "  ", h3_labels[i], " (", h3_vars[i], "): b = ",
            round(row$estimate, 4), ", p = ",
            format.pval(row$p.value, digits = 4),
            " -> ", ifelse(row$estimate > 0 & row$p.value < 0.05,
                "SUPPORTED", "NOT SUPPORTED"
            )
        )
    }
}

# VIF
vif_m3 <- check_vif(m3_reml, "Model 3")
m3_summary <- extract_model_summary(m3_reml, "Model 3: L1 Within-Person")


# =============================================================================
# [8] MODEL 4: ADD BETWEEN-PERSON COMPONENTS OF L1 VARIABLES
# =============================================================================
log_msg("=== [8] Model 4: Between-Person Components of L1 Variables ===")
log_msg(
    "  Tests contextual effects: do person-level means predict TI",
    " beyond WP effects?"
)

m4_formula <- as.formula(paste(
    "turnover_intention_mean ~ time_c +",
    "pf_mean_within + cw_mean_within + ee_mean_within +",
    "comp_mean_within + auto_mean_within + relt_mean_within +",
    "meetings_count_within + meetings_mins_within +",
    "atcb_mean_within +",
    "pf_mean_between + cw_mean_between + ee_mean_between +",
    "comp_mean_between + auto_mean_between + relt_mean_between +",
    "meetings_count_between + meetings_mins_between +",
    "atcb_mean_between +",
    re_term
))
log_msg("  Formula: ", deparse(m4_formula, width.cutoff = 200))

m4_reml <- safe_lmer(m4_formula, data = df, REML = TRUE)
m4_ml <- safe_lmer(m4_formula, data = df, REML = FALSE)

lrt_4v3 <- compare_models(m3_ml, m4_ml, "Model 3", "Model 4")
log_msg(
    "  LRT Model 4 vs 3: chi2 = ", round(lrt_4v3$chi_sq, 3),
    ", df = ", lrt_4v3$df, ", p = ", format.pval(lrt_4v3$p_value, digits = 4)
)

# Log contextual effects (BP - WP difference)
fe4 <- broom.mixed::tidy(m4_reml, effects = "fixed", conf.int = TRUE)
for (v in l1_predictor_vars) {
    wp_row <- fe4[fe4$term == paste0(v, "_within"), ]
    bp_row <- fe4[fe4$term == paste0(v, "_between"), ]
    if (nrow(wp_row) > 0 && nrow(bp_row) > 0) {
        ctx <- bp_row$estimate - wp_row$estimate
        log_msg(
            "  Contextual effect (", v, "): BP - WP = ",
            round(ctx, 4)
        )
    }
}

vif_m4 <- check_vif(m4_reml, "Model 4")
m4_summary <- extract_model_summary(
    m4_reml,
    "Model 4: L1 Within + Between"
)


# =============================================================================
# [9] MODEL 5: ADD L2 STUDY VARIABLES
# =============================================================================
log_msg("=== [9] Model 5: L2 Between-Person Study Variables ===")
log_msg("  Tests H4a-e: Affect, psych contract, job satisfaction -> TI")

m5_formula <- as.formula(paste(
    "turnover_intention_mean ~ time_c +",
    "pf_mean_within + cw_mean_within + ee_mean_within +",
    "comp_mean_within + auto_mean_within + relt_mean_within +",
    "meetings_count_within + meetings_mins_within +",
    "atcb_mean_within +",
    "pf_mean_between + cw_mean_between + ee_mean_between +",
    "comp_mean_between + auto_mean_between + relt_mean_between +",
    "meetings_count_between + meetings_mins_between +",
    "atcb_mean_between +",
    "pa_mean_c + na_mean_c + br_mean_c + vio_mean_c + js_mean_c +",
    re_term
))
log_msg("  Formula: ", deparse(m5_formula, width.cutoff = 200))

m5_reml <- safe_lmer(m5_formula, data = df, REML = TRUE)
m5_ml <- safe_lmer(m5_formula, data = df, REML = FALSE)

lrt_5v4 <- compare_models(m4_ml, m5_ml, "Model 4", "Model 5")
log_msg(
    "  LRT Model 5 vs 4: chi2 = ", round(lrt_5v4$chi_sq, 3),
    ", df = ", lrt_5v4$df, ", p = ", format.pval(lrt_5v4$p_value, digits = 4)
)

# Hypothesis tests for H4a-e
fe5 <- broom.mixed::tidy(m5_reml, effects = "fixed", conf.int = TRUE)
h4_vars <- c("pa_mean_c", "na_mean_c", "br_mean_c", "vio_mean_c", "js_mean_c")
h4_labels <- c("H4a", "H4b", "H4c", "H4d", "H4e")
h4_directions <- c("negative", "positive", "positive", "positive", "negative")
for (i in seq_along(h4_vars)) {
    row <- fe5[fe5$term == h4_vars[i], ]
    if (nrow(row) > 0) {
        expected <- if (h4_directions[i] == "positive") {
            row$estimate > 0
        } else {
            row$estimate < 0
        }
        log_msg(
            "  ", h4_labels[i], " (", h4_vars[i], "): b = ",
            round(row$estimate, 4), ", p = ",
            format.pval(row$p.value, digits = 4),
            " (expected: ", h4_directions[i], ")",
            " -> ", ifelse(expected & row$p.value < 0.05,
                "SUPPORTED", "NOT SUPPORTED"
            )
        )
    }
}

vif_m5 <- check_vif(m5_reml, "Model 5")
m5_summary <- extract_model_summary(
    m5_reml,
    "Model 5: L1 + L2 Study Variables"
)


# =============================================================================
# [10] MODEL 6: ADD DEMOGRAPHIC COVARIATES
# =============================================================================
log_msg("=== [10] Model 6: Demographic Covariates ===")
log_msg(
    "  Sensitivity check: do substantive conclusions hold after",
    " controlling for demographics?"
)

m6_formula <- as.formula(paste(
    "turnover_intention_mean ~ time_c +",
    "pf_mean_within + cw_mean_within + ee_mean_within +",
    "comp_mean_within + auto_mean_within + relt_mean_within +",
    "meetings_count_within + meetings_mins_within +",
    "atcb_mean_within +",
    "pf_mean_between + cw_mean_between + ee_mean_between +",
    "comp_mean_between + auto_mean_between + relt_mean_between +",
    "meetings_count_between + meetings_mins_between +",
    "atcb_mean_between +",
    "pa_mean_c + na_mean_c + br_mean_c + vio_mean_c + js_mean_c +",
    "age_c + gender + job_tenure + is_remote +",
    re_term
))
log_msg("  Formula: ", deparse(m6_formula, width.cutoff = 200))

m6_reml <- safe_lmer(m6_formula, data = df, REML = TRUE)
m6_ml <- safe_lmer(m6_formula, data = df, REML = FALSE)

lrt_6v5 <- compare_models(m5_ml, m6_ml, "Model 5", "Model 6")
log_msg(
    "  LRT Model 6 vs 5: chi2 = ", round(lrt_6v5$chi_sq, 3),
    ", df = ", lrt_6v5$df, ", p = ", format.pval(lrt_6v5$p_value, digits = 4)
)

# Compare H3/H4 coefficients for stability
fe6 <- broom.mixed::tidy(m6_reml, effects = "fixed", conf.int = TRUE)
log_msg("  Checking stability of substantive effects (Model 5 -> 6):")
check_stability_vars <- c(
    h3_vars, paste0(l1_predictor_vars, "_between"),
    h4_vars
)
for (v in check_stability_vars) {
    r5 <- fe5[fe5$term == v, ]
    r6 <- fe6[fe6$term == v, ]
    if (nrow(r5) > 0 && nrow(r6) > 0) {
        change <- abs(r6$estimate - r5$estimate)
        pct_change <- ifelse(abs(r5$estimate) > 0.001,
            round(change / abs(r5$estimate) * 100, 1), NA
        )
        if (!is.na(pct_change) && pct_change > 20) {
            log_msg(
                "  [NOTE] ", v, " changed >20%: ",
                round(r5$estimate, 4), " -> ", round(r6$estimate, 4),
                " (", pct_change, "% change)"
            )
        }
    }
}

vif_m6 <- check_vif(m6_reml, "Model 6")
m6_summary <- extract_model_summary(
    m6_reml,
    "Model 6: Full Model with Covariates"
)


# =============================================================================
# [11] MODEL COMPARISON TABLE
# =============================================================================
log_msg("=== [11] Building model comparison table ===")

model_names <- c(
    "Model 0: Unconditional Means",
    "Model 1: Fixed Time",
    "Model 2: Random Slope",
    "Model 3: L1 Within-Person",
    "Model 4: L1 Within + Between",
    "Model 5: L1 + L2 Study Variables",
    "Model 6: Full Model with Covariates"
)
model_fits_reml <- list(
    m0_reml, m1_reml, m2_reml, m3_reml,
    m4_reml, m5_reml, m6_reml
)
model_fits_ml <- list(
    m0_ml, m1_ml, m2_ml, m3_ml,
    m4_ml, m5_ml, m6_ml
)

# Collect fit statistics
comparison_tbl <- purrr::map2_dfr(
    model_fits_reml, model_names,
    function(fit, name) {
        if (is.null(fit)) {
            return(tibble::tibble(Model = name))
        }
        gl <- broom.mixed::glance(fit)
        r2 <- tryCatch(performance::r2_nakagawa(fit),
            error = function(e) list(R2_marginal = NA, R2_conditional = NA)
        )
        vc <- as.data.frame(VarCorr(fit))

        tau_00_val <- vc$vcov[vc$grp == "response_id" &
            vc$var1 == "(Intercept)" & is.na(vc$var2)]
        if (length(tau_00_val) == 0) tau_00_val <- NA
        sigma2_val <- vc$vcov[vc$grp == "Residual"]
        if (length(sigma2_val) == 0) sigma2_val <- NA
        tau_11_val <- vc$vcov[vc$grp == "response_id" &
            vc$var1 == "time_c" & is.na(vc$var2)]
        if (length(tau_11_val) == 0) tau_11_val <- NA

        tibble::tibble(
            Model          = name,
            AIC            = gl$AIC,
            BIC            = gl$BIC,
            logLik         = gl$logLik,
            deviance       = gl$deviance,
            n_fixed        = length(fixef(fit)),
            R2_marginal    = r2$R2_marginal,
            R2_conditional = r2$R2_conditional,
            tau_00         = tau_00_val,
            tau_11         = tau_11_val,
            sigma2         = sigma2_val
        )
    }
)

# Add LRT results
lrt_all <- dplyr::bind_rows(
    tibble::tibble(
        Model = model_names[1], LRT_chi2 = NA, LRT_df = NA,
        LRT_p = NA
    ),
    lrt_1v0 |> dplyr::transmute(
        Model = model_names[2],
        LRT_chi2 = chi_sq, LRT_df = df, LRT_p = p_value
    ),
    lrt_2v1 |> dplyr::transmute(
        Model = model_names[3],
        LRT_chi2 = chi_sq, LRT_df = df, LRT_p = p_value
    ),
    lrt_3vp |> dplyr::transmute(
        Model = model_names[4],
        LRT_chi2 = chi_sq, LRT_df = df, LRT_p = p_value
    ),
    lrt_4v3 |> dplyr::transmute(
        Model = model_names[5],
        LRT_chi2 = chi_sq, LRT_df = df, LRT_p = p_value
    ),
    lrt_5v4 |> dplyr::transmute(
        Model = model_names[6],
        LRT_chi2 = chi_sq, LRT_df = df, LRT_p = p_value
    ),
    lrt_6v5 |> dplyr::transmute(
        Model = model_names[7],
        LRT_chi2 = chi_sq, LRT_df = df, LRT_p = p_value
    )
)

comparison_tbl <- dplyr::left_join(comparison_tbl, lrt_all, by = "Model")

readr::write_csv(
    comparison_tbl,
    file.path(FIGS_DIR, "mlm_01_model_comparison.csv")
)
log_msg("  Saved model comparison CSV")

# PDF table
comparison_display <- comparison_tbl |>
    dplyr::mutate(across(where(is.numeric), ~ round(., 3)))
p_comp <- gridExtra::tableGrob(comparison_display,
    rows = NULL,
    theme = gridExtra::ttheme_minimal(base_size = 8)
)
pdf(file.path(FIGS_DIR, "mlm_01_model_comparison.pdf"),
    width = 18, height = 6
)
grid::grid.draw(p_comp)
dev.off()
log_msg("  Saved model comparison PDF")


# =============================================================================
# [12] FIXED EFFECTS SUMMARY TABLE
# =============================================================================
log_msg("=== [12] Building fixed effects summary ===")

fe_all <- purrr::map2_dfr(model_fits_reml, model_names, function(fit, name) {
    if (is.null(fit)) {
        return(tibble::tibble(model = name))
    }
    broom.mixed::tidy(fit,
        effects = "fixed", conf.int = TRUE,
        conf.level = 0.95
    ) |>
        dplyr::mutate(model = name)
})

readr::write_csv(fe_all, file.path(FIGS_DIR, "mlm_02_fixed_effects.csv"))
log_msg("  Saved fixed effects CSV")

# PDF: one sub-table per model
pdf(file.path(FIGS_DIR, "mlm_02_fixed_effects.pdf"),
    width = 14, height = 10
)
for (i in seq_along(model_names)) {
    sub_tbl <- fe_all |>
        dplyr::filter(model == model_names[i]) |>
        dplyr::select(
            term, estimate, std.error, statistic, df, p.value,
            conf.low, conf.high
        ) |>
        dplyr::mutate(across(where(is.numeric), ~ round(., 4)))

    grid::grid.newpage()
    grid::grid.draw(gridExtra::tableGrob(
        sub_tbl,
        rows = NULL,
        theme = gridExtra::ttheme_minimal(base_size = 9)
    ))
    grid::grid.text(model_names[i],
        x = 0.5, y = 0.95,
        gp = grid::gpar(fontsize = 14, fontface = "bold")
    )
}
dev.off()
log_msg("  Saved fixed effects PDF")


# =============================================================================
# [13] RANDOM EFFECTS SUMMARY TABLE
# =============================================================================
log_msg("=== [13] Building random effects summary ===")

re_all <- purrr::map2_dfr(model_fits_reml, model_names, function(fit, name) {
    if (is.null(fit)) {
        return(tibble::tibble(model = name))
    }
    broom.mixed::tidy(fit, effects = "ran_pars") |>
        dplyr::mutate(model = name)
})

readr::write_csv(re_all, file.path(FIGS_DIR, "mlm_03_random_effects.csv"))
log_msg("  Saved random effects CSV")

re_display <- re_all |>
    dplyr::mutate(across(where(is.numeric), ~ round(., 4)))
pdf(file.path(FIGS_DIR, "mlm_03_random_effects.pdf"), width = 12, height = 8)
grid::grid.draw(gridExtra::tableGrob(re_display,
    rows = NULL,
    theme = gridExtra::ttheme_minimal(base_size = 9)
))
dev.off()
log_msg("  Saved random effects PDF")


# =============================================================================
# [14] HYPOTHESIS TESTING SUMMARY
# =============================================================================
log_msg("=== [14] Building hypothesis testing summary ===")

hyp_tbl <- tibble::tribble(
    ~Hypothesis, ~Description, ~Test, ~Model,
    "H1", "Between-person variance in TI", "ICC > 0.05", "Model 0",
    "H2a", "Positive linear trend in TI", "time_c > 0 (p < .05)", "Model 1",
    "H2b", "Random slope variance > 0", "tau_11 > 0 (LRT)", "Model 2",
    "H2c", "Random > fixed slopes", "LRT M2 vs M1 (p < .05)", "Model 2",
    "H3a", "Physical fatigue -> TI (+, WP)", "pf_mean_within > 0", "Model 3",
    "H3b", "Cognitive weariness -> TI (+, WP)", "cw_mean_within > 0", "Model 3",
    "H3c", "Emotional exhaustion -> TI (+, WP)", "ee_mean_within > 0", "Model 3",
    "H3d", "Competence thwarting -> TI (+, WP)", "comp_mean_within > 0", "Model 3",
    "H3e", "Autonomy thwarting -> TI (+, WP)", "auto_mean_within > 0", "Model 3",
    "H3f", "Relatedness thwarting -> TI (+, WP)", "relt_mean_within > 0", "Model 3",
    "H3g", "Meeting count -> TI (+, WP)", "meetings_count_within > 0", "Model 3",
    "H3h", "Meeting time -> TI (+, WP)", "meetings_mins_within > 0", "Model 3",
    "H4a", "Positive affect -> TI (-, BP)", "pa_mean_c < 0", "Model 5",
    "H4b", "Negative affect -> TI (+, BP)", "na_mean_c > 0", "Model 5",
    "H4c", "PC breach -> TI (+, BP)", "br_mean_c > 0", "Model 5",
    "H4d", "PC violation -> TI (+, BP)", "vio_mean_c > 0", "Model 5",
    "H4e", "Job satisfaction -> TI (-, BP)", "js_mean_c < 0", "Model 5"
)

# Pull test results
get_coef_result <- function(fe_tbl, model_name, term_name, direction) {
    row <- fe_tbl |>
        dplyr::filter(model == model_name, term == term_name)
    if (nrow(row) == 0) {
        return(list(est = NA, p = NA, supported = NA))
    }
    est <- row$estimate[1]
    p <- row$p.value[1]
    dir_ok <- if (direction == "+") est > 0 else est < 0
    supported <- dir_ok & p < 0.05
    list(est = round(est, 4), p = p, supported = supported)
}

hyp_results <- hyp_tbl |>
    dplyr::mutate(
        Estimate = NA_real_,
        p_value = NA_real_,
        Supported = NA_character_
    )

# H1
hyp_results$Estimate[1] <- round(icc_m0$ICC_adjusted, 4)
hyp_results$p_value[1] <- NA # ICC significance not a simple p-value
hyp_results$Supported[1] <- ifelse(icc_m0$ICC_adjusted > 0.05, "Yes", "No")

# H2a
r <- get_coef_result(fe_all, "Model 1: Fixed Time", "time_c", "+")
hyp_results$Estimate[2] <- r$est
hyp_results$p_value[2] <- r$p
hyp_results$Supported[2] <- ifelse(isTRUE(r$supported), "Yes", "No")

# H2b
hyp_results$Estimate[3] <- comparison_tbl$tau_11[3]
hyp_results$p_value[3] <- lrt_2v1$p_value
hyp_results$Supported[3] <- ifelse(
    !is.na(lrt_2v1$p_value) && lrt_2v1$p_value < 0.05, "Yes", "No"
)

# H2c
hyp_results$Estimate[4] <- lrt_2v1$chi_sq
hyp_results$p_value[4] <- lrt_2v1$p_value
hyp_results$Supported[4] <- ifelse(
    !is.na(lrt_2v1$p_value) && lrt_2v1$p_value < 0.05, "Yes", "No"
)

# H3a-h
h3_terms <- c(
    "pf_mean_within", "cw_mean_within", "ee_mean_within",
    "comp_mean_within", "auto_mean_within", "relt_mean_within",
    "meetings_count_within", "meetings_mins_within"
)
for (i in seq_along(h3_terms)) {
    r <- get_coef_result(
        fe_all, "Model 3: L1 Within-Person",
        h3_terms[i], "+"
    )
    hyp_results$Estimate[4 + i] <- r$est
    hyp_results$p_value[4 + i] <- r$p
    hyp_results$Supported[4 + i] <- ifelse(isTRUE(r$supported), "Yes", "No")
}

# H4a-e
h4_terms_full <- c(
    "pa_mean_c", "na_mean_c", "br_mean_c",
    "vio_mean_c", "js_mean_c"
)
h4_dirs <- c("-", "+", "+", "+", "-")
for (i in seq_along(h4_terms_full)) {
    r <- get_coef_result(
        fe_all, "Model 5: L1 + L2 Study Variables",
        h4_terms_full[i], h4_dirs[i]
    )
    hyp_results$Estimate[12 + i] <- r$est
    hyp_results$p_value[12 + i] <- r$p
    hyp_results$Supported[12 + i] <- ifelse(isTRUE(r$supported), "Yes", "No")
}

hyp_results <- hyp_results |>
    dplyr::mutate(p_value = round(p_value, 4))

readr::write_csv(
    hyp_results,
    file.path(FIGS_DIR, "mlm_04_hypothesis_tests.csv")
)
log_msg("  Saved hypothesis tests CSV")

# PDF
p_hyp <- gridExtra::tableGrob(hyp_results,
    rows = NULL,
    theme = gridExtra::ttheme_minimal(base_size = 9)
)
pdf(file.path(FIGS_DIR, "mlm_04_hypothesis_tests.pdf"), width = 16, height = 8)
grid::grid.draw(p_hyp)
dev.off()
log_msg("  Saved hypothesis tests PDF")


# =============================================================================
# [15] ASSUMPTION DIAGNOSTICS
# =============================================================================
log_msg("=== [15] Assumption diagnostics ===")

check_assumptions(m5_reml, "Model 5")
check_assumptions(m6_reml, "Model 6")

# VIF plots for key models
save_vif_plot(vif_m5, "Model 5")
save_vif_plot(vif_m6, "Model 6")


# =============================================================================
# [16] EFFECT SIZES
# =============================================================================
log_msg("=== [16] Effect sizes ===")

# --- 16a. Standardized coefficients (beta) -----------------------------------
log_msg("  Computing standardized coefficients (method = 'basic')...")

es_models <- list(m3_reml, m5_reml, m6_reml)
es_names <- c(
    "Model 3: L1 Within-Person",
    "Model 5: L1 + L2 Study Variables",
    "Model 6: Full Model with Covariates"
)

std_effects <- purrr::map2_dfr(es_models, es_names, compute_standardized_coefs)
readr::write_csv(
    std_effects,
    file.path(FIGS_DIR, "mlm_05_standardized_effects.csv")
)
log_msg("  Saved standardized effects CSV")

# --- 16b. Level-specific pseudo-d --------------------------------------------
log_msg("  Computing level-specific pseudo-d effect sizes...")

pseudo_d_all <- purrr::map2_dfr(es_models, es_names, compute_level_specific_es)
readr::write_csv(
    pseudo_d_all,
    file.path(FIGS_DIR, "mlm_06_level_specific_es.csv")
)
log_msg("  Saved level-specific effect sizes CSV")

# Log notable effects
notable <- pseudo_d_all |>
    dplyr::filter(
        !term %in% c("(Intercept)", "time_c"),
        !is.na(pseudo_d)
    ) |>
    dplyr::arrange(dplyr::desc(abs(pseudo_d)))

if (nrow(notable) > 0) {
    log_msg("  Top 5 pseudo-d effects (absolute):")
    for (i in seq_len(min(5, nrow(notable)))) {
        log_msg(
            "    ", notable$model[i], " | ", notable$term[i],
            " | d = ", round(notable$pseudo_d[i], 3),
            " (", notable$magnitude[i], ", ", notable$level[i], ")"
        )
    }
}

# --- 16c. Delta-R² and Cohen's f² --------------------------------------------
log_msg("  Computing delta-R2 and Cohen's f2...")

delta_r2_tbl <- compute_delta_r2(comparison_tbl)
readr::write_csv(
    delta_r2_tbl,
    file.path(FIGS_DIR, "mlm_07_delta_r2.csv")
)
log_msg("  Saved delta-R2 / f2 CSV")

for (i in seq_len(nrow(delta_r2_tbl))) {
    log_msg(
        "    ", delta_r2_tbl$Model[i],
        " | dR2m = ", round(delta_r2_tbl$delta_R2_marginal[i], 4),
        " | f2 = ", round(delta_r2_tbl$f2[i], 4),
        " (", delta_r2_tbl$f2_magnitude[i], ")"
    )
}

# --- 16d. Forest plot of pseudo-d (Model 5) ----------------------------------
log_msg("  Generating effect size forest plot...")

# Use Model 5 (substantive model before demographics)
plot_data <- pseudo_d_all |>
    dplyr::filter(
        model == "Model 5: L1 + L2 Study Variables",
        !term %in% c("(Intercept)", "time_c"),
        !is.na(pseudo_d)
    ) |>
    dplyr::mutate(
        term_label = stringr::str_replace_all(term, "_", " ") |>
            stringr::str_to_title(),
        term_label = forcats::fct_reorder(term_label, pseudo_d)
    )

if (nrow(plot_data) > 0) {
    p_forest <- ggplot(plot_data, aes(
        x = pseudo_d, y = term_label,
        color = level
    )) +
        geom_vline(xintercept = 0, linetype = "dashed", color = "grey50") +
        geom_point(size = 2.5) +
        geom_errorbarh(aes(xmin = pseudo_d_lo, xmax = pseudo_d_hi),
            height = 0.2
        ) +
        # Cohen's d benchmarks
        annotate("rect",
            xmin = -0.20, xmax = 0.20,
            ymin = -Inf, ymax = Inf,
            alpha = 0.06, fill = "grey50"
        ) +
        scale_color_manual(values = c(
            "L1 (within)" = "#0072B2",
            "L2 (between)" = "#D55E00"
        )) +
        labs(
            title = "Level-Specific Effect Sizes (Pseudo-d)",
            subtitle = "Model 5: L1 + L2 Study Variables | Shaded band = negligible (|d| < 0.20)",
            x = "Pseudo-d (coefficient / level-appropriate SD of DV)",
            y = NULL,
            color = "Level"
        )
    save_pdf(p_forest, "mlm_es_forest_plot.pdf",
        width = 11, height = max(6, nrow(plot_data) * 0.4)
    )
}

# --- 16e. R² decomposition stacked bar chart ----------------------------------
log_msg("  Generating R2 decomposition chart...")

r2_plot_data <- comparison_tbl |>
    dplyr::filter(!is.na(R2_marginal)) |>
    dplyr::mutate(
        R2_random_only = R2_conditional - R2_marginal,
        R2_unexplained = 1 - R2_conditional,
        model_short = stringr::str_extract(Model, "Model \\d")
    ) |>
    dplyr::select(
        model_short, R2_marginal, R2_random_only, R2_unexplained
    ) |>
    tidyr::pivot_longer(
        cols = c(R2_marginal, R2_random_only, R2_unexplained),
        names_to = "component",
        values_to = "proportion"
    ) |>
    dplyr::mutate(
        component = factor(component,
            levels = c("R2_unexplained", "R2_random_only", "R2_marginal"),
            labels = c("Unexplained", "Random Effects Only", "Fixed Effects (Marginal)")
        )
    )

p_r2 <- ggplot(r2_plot_data, aes(
    x = model_short, y = proportion,
    fill = component
)) +
    geom_col(width = 0.7) +
    scale_fill_manual(values = c(
        "Fixed Effects (Marginal)" = "#0072B2",
        "Random Effects Only" = "#56B4E9",
        "Unexplained" = "#E0E0E0"
    )) +
    scale_y_continuous(
        labels = scales::percent_format(),
        expand = expansion(mult = c(0, 0.02))
    ) +
    labs(
        title = expression(R^2 ~ "Decomposition Across Model Building Sequence"),
        subtitle = "Nakagawa & Schielzeth (2013) marginal and conditional R-squared",
        x = NULL, y = "Proportion of Variance", fill = NULL
    ) +
    coord_flip()

save_pdf(p_r2, "mlm_es_r2_decomposition.pdf", width = 10, height = 6)


# =============================================================================
# [17] FUTURE INTERACTION MODELS (TEMPLATES ONLY)
# =============================================================================
log_msg("=== [17] Interaction model templates (not executed) ===")

# --- H5a-b: L1 x L1 Interactions (Meetings x Burnout/NF) ---
# These test whether meeting characteristics amplify the burnout->TI and NF->TI
# relationships at the within-person level.
#
# Example formulas (to be fit in a separate phase):
#
# m7a_formula <- turnover_intention_mean ~ time_c +
#     pf_mean_within + cw_mean_within + ee_mean_within +
#     comp_mean_within + auto_mean_within + relt_mean_within +
#     meetings_count_within + meetings_mins_within +
#     atcb_mean_within +
#     meetings_count_within:pf_mean_within +
#     meetings_count_within:cw_mean_within +
#     meetings_count_within:ee_mean_within +
#     meetings_count_within:comp_mean_within +
#     meetings_count_within:auto_mean_within +
#     meetings_count_within:relt_mean_within +
#     [BP terms] + [L2 terms] +
#     (1 | response_id)
#
# --- H5c-f: Cross-Level Interactions (L2 moderating L1 slopes) ---
# These require random slopes for the L1 predictor being moderated.
#
# Example (H5c: breach moderates burnout->TI):
# m7c_formula <- turnover_intention_mean ~ time_c +
#     pf_mean_within * br_mean_c +
#     cw_mean_within * br_mean_c +
#     ee_mean_within * br_mean_c +
#     [other terms] +
#     (pf_mean_within + cw_mean_within + ee_mean_within | response_id)
#
# NOTE: Cross-level interactions require random slopes for the moderated
# L1 predictor. With only 3 timepoints, this is computationally difficult.
# Consider testing one interaction at a time in separate models.

log_msg("  Interaction templates documented; not fitted in this run.")


# =============================================================================
# [18] SESSION SUMMARY
# =============================================================================
log_msg("=== [18] Session Summary ===")

csv_files <- list.files(FIGS_DIR, pattern = "\\.csv$")
pdf_files <- list.files(FIGS_DIR, pattern = "\\.pdf$")
log_msg("Output directory: ", FIGS_DIR)
log_msg("CSV files generated: ", length(csv_files))
log_msg("PDF files generated: ", length(pdf_files))
log_msg("")
log_msg("Random effects decision: ", re_note)
log_msg("Models fitted: 0 (null) through 6 (full with covariates)")
log_msg("")
log_msg("=== MULTILEVEL MODEL BUILDING COMPLETE ===")

cat("\n=== Session Info ===\n")
sessionInfo()
