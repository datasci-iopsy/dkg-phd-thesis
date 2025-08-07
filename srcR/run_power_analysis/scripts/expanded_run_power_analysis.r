#!/usr/bin/env Rscript

# ============================================================================
# Enhanced Power Analysis for Two-Level Models with Multiple Level-1 Predictors
# Based on: Arend & Schäfer (2019) with multicollinearity extensions
# See Claude 4.0 response: https://www.perplexity.ai/search/i-built-a-simulation-program-i-8QLsOXK.Q3S_c8mcGZZHuA#1
# ============================================================================

library(dplyr)
library(lme4)
library(tibble)
library(tidyr)
library(simr)
library(MASS) # For multivariate normal generation

#' Calculate Variance Inflation Factors
#'
#' @param correlation_matrix Correlation matrix between Level-1 predictors
#' @return Vector of VIF values
calculate_vif <- function(correlation_matrix) {
    if (nrow(correlation_matrix) == 1) {
        return(1.0)
    }

    # VIF_k = 1 / (1 - R²_k) where R²_k comes from regressing X_k on other X's
    vif_values <- diag(solve(correlation_matrix))
    names(vif_values) <- rownames(correlation_matrix)

    return(vif_values)
}

#' Generate Correlated Level-1 Predictors
#'
#' @param n_lvl1 Level 1 sample size
#' @param n_lvl2 Level 2 sample size
#' @param correlation_matrix Correlation matrix between predictors
#' @param predictor_names Names for predictors
generate_correlated_predictors <- function(n_lvl1, n_lvl2, correlation_matrix, predictor_names) {
    n_predictors <- nrow(correlation_matrix)
    total_n <- n_lvl1 * n_lvl2

    # Generate multivariate normal data
    raw_predictors <- MASS::mvrnorm(
        n = total_n,
        mu = rep(0, n_predictors),
        Sigma = correlation_matrix
    )

    # Convert to data frame and add group structure
    predictor_data <- as.data.frame(raw_predictors)
    names(predictor_data) <- predictor_names

    # Add grouping variables
    predictor_data$g <- as.factor(rep(1:n_lvl2, each = n_lvl1))

    # Within-cluster center each predictor (critical for Level-1 effects)
    predictor_data <- predictor_data |>
        group_by(g) |>
        mutate(across(all_of(predictor_names), ~ scale(.x)[, 1])) |>
        ungroup()

    return(predictor_data)
}

#' Enhanced Power Analysis Function for Multiple Level-1 Predictors
#'
#' @param n_lvl1 Level 1 sample size
#' @param n_lvl2 Level 2 sample size
#' @param lvl1_effects_std Vector of standardized L1 direct effects
#' @param lvl1_predictor_names Names for L1 predictors
#' @param lvl1_correlation_matrix Correlation matrix between L1 predictors
#' @param lvl2_effect_std Standardized L2 direct effect (default: 0.30)
#' @param xlvl_effects_std Vector of standardized cross-level interaction effects
#' @param icc Intraclass correlation coefficient (default: 0.30)
#' @param rand_slope_std Vector of standardized random slope variances
#' @param alpha Significance level (default: 0.05)
#' @param use_REML Boolean to use REML (default: TRUE)
#' @param n_sims Number of simulations (default: 1000)
#' @param verbose Print detailed output (default: TRUE)
#' @param return_df Return results as data frame (default: FALSE)
#' @param rand_seed Random seed (default: 1234)
#' @param adjust_for_multicollinearity Apply VIF adjustments (default: TRUE)
#'
enhanced_power_analysis_two_level <- function(
    n_lvl1,
    n_lvl2,
    lvl1_effects_std = c(0.30),
    lvl1_predictor_names = paste0("x", seq_along(lvl1_effects_std)),
    lvl1_correlation_matrix = diag(length(lvl1_effects_std)),
    lvl2_effect_std = 0.30,
    xlvl_effects_std = rep(0.50, length(lvl1_effects_std)),
    icc = 0.30,
    rand_slope_std = rep(0.09, length(lvl1_effects_std)),
    alpha = 0.05,
    use_REML = TRUE,
    n_sims = 1000,
    verbose = TRUE,
    return_df = FALSE,
    rand_seed = 1234,
    adjust_for_multicollinearity = TRUE) {
    # Input validation
    n_predictors <- length(lvl1_effects_std)

    if (nrow(lvl1_correlation_matrix) != n_predictors ||
        ncol(lvl1_correlation_matrix) != n_predictors) {
        stop("Correlation matrix dimensions must match number of Level-1 predictors")
    }

    if (length(xlvl_effects_std) != n_predictors) {
        stop("Cross-level effects must match number of Level-1 predictors")
    }

    if (length(rand_slope_std) != n_predictors) {
        stop("Random slope variances must match number of Level-1 predictors")
    }

    # Calculate VIF values
    vif_values <- calculate_vif(lvl1_correlation_matrix)
    max_vif <- max(vif_values)

    if (verbose) {
        cat("Multicollinearity Assessment:\n")
        cat(sprintf("VIF values: %s\n", paste(round(vif_values, 3), collapse = ", ")))
        cat(sprintf("Maximum VIF: %.3f\n", max_vif))
        if (max_vif > 5) {
            cat("WARNING: High multicollinearity detected (VIF > 5)\n")
        } else if (max_vif > 2) {
            cat("CAUTION: Moderate multicollinearity detected (VIF > 2)\n")
        }
        cat("\n")
    }

    # Step 1: Calculate variance components (following Arend & Schäfer)
    var_lvl1_uncond <- 1.00
    var_lvl2_uncond <- icc / (1 - icc)
    var_random_slopes_uncond <- rand_slope_std * var_lvl1_uncond

    # Conditional variances (Equation 11 extended for multiple predictors)
    # Note: This assumes predictors explain independent portions of variance
    total_r2_l1 <- sum(lvl1_effects_std^2)
    var_lvl1_cond <- var_lvl1_uncond * (1 - total_r2_l1)

    var_lvl2_cond <- var_lvl2_uncond * (1 - lvl2_effect_std^2)

    var_random_slopes_cond <- var_random_slopes_uncond * (1 - xlvl_effects_std^2)

    # Step 2: Calculate population effects (Equation 15 extended)
    lvl1_effects_pop <- lvl1_effects_std * sqrt(var_lvl1_uncond)
    lvl2_effect_pop <- lvl2_effect_std * sqrt(var_lvl2_uncond)
    xlvl_effects_pop <- xlvl_effects_std * sqrt(var_random_slopes_uncond)

    # Step 3: Generate correlated predictor data
    set.seed(rand_seed)
    data_struct <- generate_correlated_predictors(
        n_lvl1, n_lvl2,
        lvl1_correlation_matrix,
        lvl1_predictor_names
    )

    # Add Level-2 predictor
    data_struct$Z <- scale(as.numeric(data_struct$g))[, 1]

    # Step 4: Build enhanced population model
    # Fixed effects: intercept + L1 effects + L2 effect + cross-level interactions
    fixed_effects <- c(
        0, # intercept
        lvl1_effects_pop, # L1 direct effects
        lvl2_effect_pop, # L2 direct effect
        xlvl_effects_pop # Cross-level interactions
    )

    # Step 5: Construct random effects covariance matrix
    # Dimensions: (1 + n_predictors) × (1 + n_predictors)
    # [intercept, slope1, slope2, ..., slopeK]
    random_dim <- 1 + n_predictors
    random_effects_matrix <- matrix(0, nrow = random_dim, ncol = random_dim)

    # Set diagonal elements
    random_effects_matrix[1, 1] <- var_lvl2_cond # intercept variance
    for (i in seq_len(n_predictors)) {
        random_effects_matrix[i + 1, i + 1] <- var_random_slopes_cond[i] # slope variances
    }

    # Set off-diagonal elements to zero (conservative assumption)
    # Could be extended to allow correlations between random effects

    # Step 6: Create model formula dynamically
    l1_terms <- paste(lvl1_predictor_names, collapse = " + ")
    interaction_terms <- paste(paste0("Z:", lvl1_predictor_names), collapse = " + ")
    random_terms <- paste0("(", paste(lvl1_predictor_names, collapse = " + "), " | g)")

    model_formula <- as.formula(paste0(
        "y ~ ", l1_terms, " + Z + ", interaction_terms, " + ", random_terms
    ))

    if (verbose) {
        cat("Model Formula:", deparse(model_formula), "\n\n")
    }

    # Step 7: Create population model using SIMR
    population_model <- simr::makeLmer(
        formula = model_formula,
        fixef = fixed_effects,
        VarCorr = random_effects_matrix,
        sigma = sqrt(var_lvl1_cond),
        data = data_struct
    )

    if (verbose) {
        cat("Population Model Created Successfully\n")
        cat("Running Power Simulations...\n\n")
    }

    # Step 8: Run power simulations for each effect
    run_power <- function(effect_name, test_spec) {
        if (verbose) cat(sprintf("Analyzing %s...", effect_name))

        result <- simr::powerSim(
            fit = population_model,
            test = test_spec,
            alpha = alpha,
            nsim = n_sims,
            seed = rand_seed + sample(1:1000, 1), # Ensure different seeds
            fitOpts = list(REML = use_REML)
        )

        power_value <- result$x / result$n

        if (verbose) {
            cat(sprintf(
                " Power = %.3f [%.3f, %.3f]\n",
                power_value,
                confint(result)[1],
                confint(result)[2]
            ))
        }

        return(list(
            effect = effect_name,
            power = power_value,
            lower_ci = confint(result)[1],
            upper_ci = confint(result)[2],
            result_obj = result
        ))
    }

    # Power analyses for all effects
    power_results <- list()

    # Level-1 direct effects
    for (i in seq_len(n_predictors)) {
        effect_name <- paste0("L1_Direct_", lvl1_predictor_names[i])
        power_results[[effect_name]] <- run_power(
            effect_name,
            fixed(lvl1_predictor_names[i], "kr")
        )
    }

    # Level-2 direct effect
    power_results[["L2_Direct"]] <- run_power("L2 Direct Effect", fixed("Z", "kr"))

    # Cross-level interactions
    for (i in seq_len(n_predictors)) {
        effect_name <- paste0("CLI_", lvl1_predictor_names[i])
        interaction_term <- paste0("Z:", lvl1_predictor_names[i])
        power_results[[effect_name]] <- run_power(
            effect_name,
            fixed(interaction_term, "kr")
        )
    }

    # Step 9: Apply multicollinearity adjustments if requested
    if (adjust_for_multicollinearity && max_vif > 1.01) {
        if (verbose) {
            cat("\nApplying multicollinearity adjustments...\n")
        }

        # Adjust Level-1 direct effects based on their individual VIFs
        for (i in seq_len(n_predictors)) {
            effect_name <- paste0("L1_Direct_", lvl1_predictor_names[i])
            if (effect_name %in% names(power_results)) {
                original_power <- power_results[[effect_name]]$power
                adjusted_power <- original_power / sqrt(vif_values[i])
                power_results[[effect_name]]$power_adjusted <- adjusted_power

                if (verbose) {
                    cat(sprintf(
                        "%s: %.3f → %.3f (VIF = %.3f)\n",
                        effect_name, original_power, adjusted_power, vif_values[i]
                    ))
                }
            }
        }
    }

    # Step 10: Create comprehensive summary
    effect_names <- names(power_results)
    power_summary <- tibble(
        Effect = effect_names,
        Power = map_dbl(power_results, ~ .x$power),
        Lower_CI = map_dbl(power_results, ~ .x$lower_ci),
        Upper_CI = map_dbl(power_results, ~ .x$upper_ci)
    )

    # Add adjusted power if calculated
    if (adjust_for_multicollinearity && max_vif > 1.01) {
        power_summary$Power_Adjusted <- map_dbl(power_results, function(x) {
            ifelse(!is.null(x$power_adjusted), x$power_adjusted, x$power)
        })
    }

    # Extended summary with parameters
    power_summary_extended <- power_summary |>
        mutate(
            N_Level1 = n_lvl1,
            N_Level2 = n_lvl2,
            ICC = icc,
            Max_VIF = max_vif,
            Alpha = alpha,
            N_Sims = n_sims
        )

    # Compile results
    results <- list(
        population_model = population_model,
        sample_sizes = list(n_lvl1 = n_lvl1, n_lvl2 = n_lvl2),
        multicollinearity = list(
            correlation_matrix = lvl1_correlation_matrix,
            vif_values = vif_values,
            max_vif = max_vif
        ),
        power_results = power_results,
        power_summary = power_summary,
        power_summary_extended = power_summary_extended,
        parameters = list(
            lvl1_effects_std = lvl1_effects_std,
            lvl2_effect_std = lvl2_effect_std,
            xlvl_effects_std = xlvl_effects_std,
            icc = icc,
            rand_slope_std = rand_slope_std,
            alpha = alpha,
            n_sims = n_sims,
            adjust_for_multicollinearity = adjust_for_multicollinearity
        )
    )

    if (verbose) {
        cat(strrep("*", 70))
        cat("\nENHANCED POWER ANALYSIS SUMMARY\n")
        cat(strrep("*", 70))
        cat(sprintf("\nSample Sizes: n_lvl1 = %d, n_lvl2 = %d\n", n_lvl1, n_lvl2))
        cat(sprintf("Number of Level-1 Predictors: %d\n", n_predictors))
        cat(sprintf("Maximum VIF: %.3f\n", max_vif))
        cat("\nPower Results:\n")
        print(power_summary)
        if (adjust_for_multicollinearity && max_vif > 1.01) {
            cat("\nNote: Power_Adjusted accounts for multicollinearity effects\n")
        }
    }

    class(results) <- "enhanced_power_analysis_2level"

    if (return_df) {
        return(power_summary_extended)
    }

    return(results)
}

#' Enhanced print method
print.enhanced_power_analysis_2level <- function(x, ...) {
    cat("Enhanced Two-Level Power Analysis Results\n")
    cat("==========================================\n")
    cat(sprintf(
        "Sample Sizes: n_lvl1 = %d, n_lvl2 = %d\n",
        x$sample_sizes$n_lvl1, x$sample_sizes$n_lvl2
    ))
    cat(sprintf("Maximum VIF: %.3f\n", x$multicollinearity$max_vif))
    cat("\nPower Results:\n")
    print(x$power_summary)
    return(invisible(x))
}

#' Extract enhanced power summary
extract_enhanced_power_data <- function(power_results, extended = TRUE) {
    if (!inherits(power_results, "enhanced_power_analysis_2level")) {
        stop("Input must be an enhanced_power_analysis_2level object")
    }

    if (extended && !is.null(power_results$power_summary_extended)) {
        return(power_results$power_summary_extended)
    } else {
        return(power_results$power_summary)
    }
}

correlation_matrix <- matrix(c(
    1.0, 0.3, 0.2,
    0.3, 1.0, 0.4,
    0.2, 0.4, 1.0
), nrow = 3)
correlation_matrix

results <- enhanced_power_analysis_two_level(
    n_lvl1 = 10,
    n_lvl2 = 100,
    lvl1_effects_std = c(0.30, 0.25, 0.20),
    lvl1_predictor_names = c("Motivation", "Ability", "Opportunity"),
    lvl1_correlation_matrix = correlation_matrix,
    xlvl_effects_std = c(0.40, 0.35, 0.30),
    icc = 0.30,
    n_sims = 1000,
    adjust_for_multicollinearity = TRUE
)
