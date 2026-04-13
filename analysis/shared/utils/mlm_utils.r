#!/usr/bin/env Rscript

# ---------------------------------------------------------------------------
# mlm_utils.r - Shared multilevel modeling helpers
#
# Provides:
#   safe_lmer()               - lmer with optimizer fallback + singularity check
#   extract_model_summary()   - tidy fixed/random/fit/R2 summary list
#   compare_models()          - likelihood ratio test wrapper
#   check_vif()               - VIF via performance::check_collinearity
#   save_vif_plot()           - VIF bar chart to SVG
#   compute_standardized_coefs()   - beta coefficients via effectsize
#   compute_level_specific_es()    - level-appropriate pseudo-d effect sizes
#   compute_delta_r2()             - delta-R2 and Cohen's f2 between models
#   verify_centering()             - confirm within-person means are ~0
#   select_covariates_bivariate()  - Bernerth & Aguinis (2016) covariate screen
#
# Dependencies: lme4, lmerTest, broom.mixed, performance, effectsize,
#               dplyr, tibble, stringr, forcats, ggplot2, purrr
# Assumes common_utils.r (log_msg) and plot_utils.r (save_svg) are sourced first.
# ---------------------------------------------------------------------------

library(lme4)
library(lmerTest)
library(broom.mixed)
library(performance)
library(effectsize)
library(dplyr)
library(tibble)
library(stringr)
library(forcats)
library(ggplot2)
library(purrr)


# ---------------------------------------------------------------------------
# [1] Model fitting
# ---------------------------------------------------------------------------

#' Fit lmer with optimizer fallback and singularity check
#'
#' @param formula  Model formula
#' @param data     Data frame
#' @param REML     Logical; TRUE for REML, FALSE for ML
#' @param ctrl     lmerControl object; defaults to bobyqa with 200k iterations
#' @return Fitted lmerModLmerTest or NULL on failure
#'
safe_lmer <- function(formula, data, REML = TRUE, ctrl = NULL) {
    if (is.null(ctrl)) {
        ctrl <- lme4::lmerControl(
            optimizer = "bobyqa",
            optCtrl = list(maxfun = 200000)
        )
    }

    fit <- tryCatch(
        lmerTest::lmer(formula, data = data, REML = REML, control = ctrl),
        error = function(e) {
            log_msg("  [WARN] bobyqa failed: ", conditionMessage(e))
            log_msg("  [WARN] Retrying with nloptwrap/nlminb...")
            ctrl2 <- lme4::lmerControl(
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

    if (!is.null(fit) && lme4::isSingular(fit)) {
        log_msg("  [WARN] Singular fit detected (near-zero variance component)")
    }

    return(fit)
}


# ---------------------------------------------------------------------------
# [2] Model extraction and comparison
# ---------------------------------------------------------------------------

#' Extract a standardized summary tibble from a fitted lmer model
#'
#' @param fit        Fitted lmerModLmerTest (or NULL)
#' @param model_name Character label for this model
#' @return Named list: $fixed, $random, $fit (glance), $r2
#'
extract_model_summary <- function(fit, model_name) {
    if (is.null(fit)) {
        return(tibble::tibble(model = model_name, note = "Model failed to converge"))
    }

    fe <- broom.mixed::tidy(fit,
        effects = "fixed", conf.int = TRUE,
        conf.level = 0.95
    ) |>
        dplyr::mutate(model = model_name)

    re <- broom.mixed::tidy(fit, effects = "ran_pars") |>
        dplyr::mutate(model = model_name)

    gl <- broom.mixed::glance(fit) |>
        dplyr::mutate(model = model_name)

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
#'
#' @param fit_a  Fitted ML model (the simpler/baseline)
#' @param fit_b  Fitted ML model (the more complex)
#' @param name_a Character label for model A
#' @param name_b Character label for model B
#' @return Tibble with comparison, chi_sq, df, p_value
#'
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


# ---------------------------------------------------------------------------
# [3] Diagnostics
# ---------------------------------------------------------------------------

#' Check multicollinearity and return VIF tibble
#'
#' @param fit        Fitted lmer model
#' @param model_name Character label for logging
#' @return Tibble of VIF values; empty tibble on failure
#'
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


#' Save a VIF bar chart as SVG
#'
#' @param vif_tbl    Tibble returned by check_vif()
#' @param model_name Character label (used in plot title and filename)
#' @param figs_dir   Directory to save to; if NULL, returns the ggplot invisibly
#' @return NULL (side effect) or ggplot object (if figs_dir is NULL)
#'
save_vif_plot <- function(vif_tbl, model_name, figs_dir = NULL) {
    if (nrow(vif_tbl) == 0) {
        return(invisible(NULL))
    }

    p <- vif_tbl |>
        dplyr::mutate(
            Term = forcats::fct_reorder(Term, VIF),
            flag = ifelse(VIF > 5, "High (>5)", "Acceptable")
        ) |>
        ggplot2::ggplot(ggplot2::aes(x = Term, y = VIF, fill = flag)) +
        ggplot2::geom_col() +
        ggplot2::geom_hline(yintercept = 5, linetype = "dashed", color = "orange") +
        ggplot2::geom_hline(yintercept = 10, linetype = "dashed", color = "red") +
        ggplot2::coord_flip() +
        ggplot2::scale_fill_manual(values = c(
            "Acceptable" = "steelblue",
            "High (>5)" = "tomato"
        )) +
        ggplot2::labs(
            title = paste("Variance Inflation Factors:", model_name),
            x = NULL, y = "VIF", fill = NULL
        )

    if (!is.null(figs_dir)) {
        filename <- file.path(
            figs_dir,
            paste0("mlm_vif_", gsub("[^a-z0-9]+", "_", tolower(model_name)), ".svg")
        )
        save_svg(p, filename,
            width = 10,
            height = max(6, nrow(vif_tbl) * 0.35)
        )
    } else {
        return(invisible(p))
    }
}


# ---------------------------------------------------------------------------
# [4] Effect sizes
# ---------------------------------------------------------------------------

#' Standardized coefficients via effectsize (method = "basic")
#'
#' The "basic" method post-hoc divides each coefficient by (SD_x / SD_y).
#' Unlike "refit" (re-fits on z-scored data; can fail on complex random
#' structures), "basic" is algebraically equivalent for continuous predictors
#' and far more stable.
#'
#' @param fit        Fitted lmer model
#' @param model_name Character label
#' @return Tibble of standardized coefficients
#'
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
#'   - L1 within-person terms  -> sigma (within-person SD of DV)
#'   - L2 between-person terms -> sqrt(tau_00) (between-person SD of DV)
#'   - Intercept / time        -> total SD as reference
#'
#' Consistent with Arend & Schafer (2019) and recommended by Lorah (2018).
#'
#' @param fit        Fitted lmer model
#' @param model_name Character label
#' @return Tibble with pseudo_d, pseudo_d_lo, pseudo_d_hi, magnitude
#'
compute_level_specific_es <- function(fit, model_name) {
    if (is.null(fit)) {
        return(tibble::tibble(model = model_name, note = "Model is NULL"))
    }

    vc <- as.data.frame(VarCorr(fit))
    sigma_val <- sqrt(vc$vcov[vc$grp == "Residual"])
    tau_00_row <- vc$vcov[
        vc$grp == "response_id" & vc$var1 == "(Intercept)" & is.na(vc$var2)
    ]
    tau_00_sd <- if (length(tau_00_row) > 0) sqrt(tau_00_row) else NA_real_

    fe <- broom.mixed::tidy(fit,
        effects = "fixed", conf.int = TRUE,
        conf.level = 0.95
    )

    fe |>
        dplyr::mutate(
            level = dplyr::case_when(
                term == "(Intercept)" ~ "intercept",
                term == "time_c" ~ "time",
                stringr::str_ends(term, "_within") ~ "L1 (within)",
                stringr::str_ends(term, "_between") ~ "L2 (between)",
                TRUE ~ "L2 (between)"
            ),
            sd_dv = dplyr::case_when(
                level == "L1 (within)" ~ sigma_val,
                level == "L2 (between)" ~ tau_00_sd,
                TRUE ~ sqrt(sigma_val^2 + tau_00_sd^2)
            ),
            pseudo_d    = estimate / sd_dv,
            pseudo_d_lo = conf.low / sd_dv,
            pseudo_d_hi = conf.high / sd_dv,
            magnitude = dplyr::case_when(
                is.na(pseudo_d) ~ NA_character_,
                abs(pseudo_d) < 0.20 ~ "negligible",
                abs(pseudo_d) < 0.50 ~ "small",
                abs(pseudo_d) < 0.80 ~ "medium",
                TRUE ~ "large"
            ),
            model = model_name
        ) |>
        dplyr::select(
            model, term, level, estimate, std.error,
            pseudo_d, pseudo_d_lo, pseudo_d_hi, sd_dv, magnitude
        )
}


#' Delta-R2 and Cohen's f2 between sequential models
#'
#' f2 = delta_R2 / (1 - R2_full). Benchmarks: .02 = small, .15 = medium,
#' .35 = large (Cohen 1988).
#'
#' @param comparison_tbl Tibble with columns Model, R2_marginal, R2_conditional
#' @return Tibble with delta_R2_marginal, delta_R2_conditional, f2, f2_magnitude
#'
compute_delta_r2 <- function(comparison_tbl) {
    r2_full <- as.numeric(max(comparison_tbl$R2_marginal, na.rm = TRUE))
    denom <- if (r2_full < 1) (1 - r2_full) else NA_real_

    comparison_tbl |>
        dplyr::arrange(match(Model, comparison_tbl$Model)) |>
        dplyr::mutate(
            delta_R2_marginal = R2_marginal - dplyr::lag(R2_marginal, default = 0),
            delta_R2_conditional = R2_conditional -
                dplyr::lag(R2_conditional, default = 0),
            f2 = delta_R2_marginal / denom,
            f2_magnitude = dplyr::case_when(
                is.na(f2) ~ NA_character_,
                f2 < 0.02 ~ "negligible",
                f2 < 0.15 ~ "small",
                f2 < 0.35 ~ "medium",
                TRUE ~ "large"
            )
        ) |>
        dplyr::select(
            Model, R2_marginal, R2_conditional,
            delta_R2_marginal, delta_R2_conditional,
            f2, f2_magnitude
        )
}


# ---------------------------------------------------------------------------
# [5] Data preparation helpers
# ---------------------------------------------------------------------------

#' Verify that person-mean centering produced within-person means of ~0
#'
#' After datawizard::demean(), each person's mean on every _within variable
#' should be (near) zero. Returns a summary table and flags any violations.
#'
#' @param df          Data frame post-centering
#' @param id_col      Character; name of the person-ID column
#' @param within_vars Character vector of _within column names to check
#' @return Named list: $table (tibble per variable), $max_deviation (scalar),
#'         $all_pass (logical)
#'
verify_centering <- function(df, id_col, within_vars) {
    within_vars <- intersect(within_vars, names(df))

    wp_check <- df |>
        dplyr::group_by(.data[[id_col]]) |>
        dplyr::summarise(
            dplyr::across(dplyr::all_of(within_vars), ~ mean(., na.rm = TRUE)),
            .groups = "drop"
        ) |>
        dplyr::summarise(
            dplyr::across(dplyr::all_of(within_vars), ~ max(abs(.), na.rm = TRUE))
        )

    result <- tibble::tibble(
        variable      = within_vars,
        max_deviation = as.numeric(wp_check[1, ])
    ) |>
        dplyr::mutate(pass = max_deviation < 1e-6)

    max_dev <- max(result$max_deviation, na.rm = TRUE)

    if (!all(result$pass)) {
        failing <- result |> dplyr::filter(!pass)
        log_msg(
            "  [WARN] Centering check failed for: ",
            paste(failing$variable, collapse = ", ")
        )
    }

    list(
        table         = result,
        max_deviation = max_dev,
        all_pass      = all(result$pass)
    )
}


#' Data-driven covariate screening per Bernerth & Aguinis (2016)
#'
#' Computes the bivariate association between each candidate covariate and the
#' dependent variable:
#'   - Continuous covariates: Pearson r via cor.test()
#'   - Factor / character covariates: eta-squared from one-way ANOVA
#'     (sqrt(eta2) reported as r-equivalent for comparability)
#'
#' Returns candidates with |r| >= r_threshold as selected.
#'
#' @param df           Data frame (long format, one row per observation)
#' @param dv           Character; name of the dependent variable column
#' @param candidates   Character vector of candidate covariate names
#' @param r_threshold  Numeric; minimum |r| to retain (default 0.10)
#' @return Named list: $cor_table (tibble), $selected (character), $excluded (character)
#'
select_covariates_bivariate <- function(df, dv, candidates, r_threshold = 0.10) {
    dv_col <- df[[dv]]

    cor_rows <- purrr::map(candidates, function(v) {
        if (!v %in% names(df)) {
            return(tibble::tibble(
                variable = v, r = NA_real_, p = NA_real_, type = "missing"
            ))
        }

        col <- df[[v]]

        if (is.factor(col) || is.character(col)) {
            fmla <- as.formula(paste(dv, "~", v))
            aov_res <- tryCatch(
                aov(fmla, data = df),
                error = function(e) NULL
            )
            if (is.null(aov_res)) {
                return(tibble::tibble(
                    variable = v, r = NA_real_, p = NA_real_, type = "factor/eta"
                ))
            }
            aov_tbl <- summary(aov_res)[[1]]
            ss_group <- aov_tbl[["Sum Sq"]][1]
            ss_total <- sum(aov_tbl[["Sum Sq"]])
            eta2  <- ss_group / ss_total
            p_val <- aov_tbl[["Pr(>F)"]][1]
            tibble::tibble(
                variable = v,
                r        = sqrt(eta2),
                p        = p_val,
                type     = "factor/eta"
            )
        } else {
            col_num <- as.numeric(col)
            ct <- tryCatch(
                cor.test(col_num, dv_col, use = "complete.obs"),
                error = function(e) NULL
            )
            if (is.null(ct)) {
                return(tibble::tibble(
                    variable = v, r = NA_real_, p = NA_real_, type = "continuous"
                ))
            }
            tibble::tibble(
                variable = v,
                r        = as.numeric(ct$estimate),
                p        = ct$p.value,
                type     = "continuous"
            )
        }
    }) |>
        dplyr::bind_rows()

    selected <- cor_rows |>
        dplyr::filter(!is.na(r), abs(r) >= r_threshold) |>
        dplyr::pull(variable)

    excluded <- setdiff(candidates, selected)

    list(
        cor_table = cor_rows,
        selected  = selected,
        excluded  = excluded
    )
}
