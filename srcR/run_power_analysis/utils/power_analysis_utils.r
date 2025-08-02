#!/usr/bin/env Rscript

# ============================================================================
# Power Analysis for Two-Level Models
# Based on: Arend & Schäfer (2019) - Enhanced with data extraction methods
# ============================================================================

# import packages
library(dplyr)
library(lme4)
library(tibble)
library(tidyr)
library(simr)

#' Main Power Analysis Function (Enhanced)
#'
#' @param n_lvl1 Level 1 sample size (repeated measures)
#' @param n_lvl2 Level 2 sample size (individuals)
#' @param lvl1_effect_std Standardized L1 direct effect (default: 0.30)
#' @param lvl2_effect_std Standardized L2 direct effect (default: 0.30)
#' @param xlvl_effect_std Standardized cross-level interaction effect (default: 0.50)
#' @param icc Intraclass correlation coefficient (default: 0.30)
#' @param rand_slope_std Standardized random slope variance (default: 0.09)
#' @param alpha Significance level (default: 0.05)
#' @param use_REML Boolean to use REML (default: TRUE)
#' @param n_sims Number of simulations (default: 1000)
#' @param verbose Print detailed output (default: TRUE)
#' @param return_df Return results as data frame (default: FALSE)
#' @param rand_seed Random seed (default: 1234)
#' @return Results object
#'
power_analysis_two_level <- function(
    n_lvl1, # nolint
    n_lvl2,
    lvl1_effect_std = 0.30,
    lvl2_effect_std = 0.30,
    xlvl_effect_std = 0.50,
    icc = 0.30,
    rand_slope_std = 0.09,
    alpha = 0.05,
    use_REML = TRUE, # nolint
    n_sims = 1000,
    verbose = TRUE,
    return_df = FALSE,
    rand_seed = 1234) {
    # Step 1: Calculate variance components (Equations 10-11 from article)
    var_lvl1_uncond <- 1.00
    var_lvl2_uncond <- icc / (1 - icc)
    var_random_slope_uncond <- rand_slope_std * var_lvl1_uncond

    # Conditional variances (Equation 11)
    var_lvl1_cond <- var_lvl1_uncond * (1 - lvl1_effect_std^2)
    var_lvl2_cond <- var_lvl2_uncond * (1 - lvl2_effect_std^2)
    var_random_slope_cond <- var_random_slope_uncond * (1 - xlvl_effect_std^2)

    # Step 2: Calculate population effects (Equation 15)
    lvl1_effect_pop <- lvl1_effect_std * sqrt(var_lvl1_uncond)
    lvl2_effect_pop <- lvl2_effect_std * sqrt(var_lvl2_uncond)
    xlvl_effect_pop <- xlvl_effect_std * sqrt(var_random_slope_uncond)

    # Step 3: Create data structure
    x <- scale(rep(1:n_lvl1))
    g <- as.factor(1:n_lvl2)
    data_struct <- expand.grid(x = as.vector(x), g = g)
    data_struct$Z <- scale(as.numeric(data_struct$g))

    # Step 4: Build population model
    fixed_effects <- c(0, lvl1_effect_pop, lvl2_effect_pop, xlvl_effect_pop)

    random_effects_matrix <- matrix(
        c(
            var_lvl2_cond, 0,
            0, var_random_slope_cond
        ),
        nrow = 2, ncol = 2
    )

    population_model <- simr::makeLmer(
        formula = y ~ x * Z + (x | g),
        fixef = fixed_effects,
        VarCorr = random_effects_matrix,
        sigma = sqrt(var_lvl1_cond),
        data = data_struct
    )

    if (verbose) {
        cat("Population Model Created Successfully\n")
        cat("Running Power Simulations...\n\n")
    }

    # Step 5: Run power simulations
    run_power <- function(effect_name, test_spec) {
        if (verbose) cat(sprintf("Analyzing %s...", effect_name))
        result <- simr::powerSim(
            fit = population_model,
            test = test_spec,
            alpha = alpha,
            nsim = n_sims,
            seed = rand_seed,
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

    # Conduct power analyses
    power_lvl1 <- run_power("L1 Direct Effect", fixed("x", "kr"))
    power_lvl2 <- run_power("L2 Direct Effect", fixed("Z", "kr"))
    power_xlvl <- run_power("Cross-Level Interaction", fixed("x:Z", "kr"))

    # Create comprehensive summary data frame
    power_summary_extended <- tibble::tibble(
        Effect = c("L1_Direct", "L2_Direct", "Cross_Level_Interaction"),
        # Effect_Label = c("L1 Direct", "L2 Direct", "Cross-Level Interaction"),
        Power = c(power_lvl1$power, power_lvl2$power, power_xlvl$power),
        Lower_CI = c(power_lvl1$lower_ci, power_lvl2$lower_ci, power_xlvl$lower_ci),
        Upper_CI = c(power_lvl1$upper_ci, power_lvl2$upper_ci, power_xlvl$upper_ci),
        N_Level1 = n_lvl1,
        N_Level2 = n_lvl2,
        Level1_Effect_Std = lvl1_effect_std,
        Level2_Effect_Std = lvl2_effect_std,
        XLevel_Intxn_Effect_Std = xlvl_effect_std,
        ICC = icc,
        Random_Slope_Std = rand_slope_std,
        Alpha = alpha,
        N_Sims = n_sims
    )

    # Original summary for backward compatibility
    power_summary <- tibble::tibble(
        Effect = c("L1 Direct", "L2 Direct", "Cross-Level Interaction"),
        Power = c(power_lvl1$power, power_lvl2$power, power_xlvl$power),
        Lower_CI = c(power_lvl1$lower_ci, power_lvl2$lower_ci, power_xlvl$lower_ci),
        Upper_CI = c(power_lvl1$upper_ci, power_lvl2$upper_ci, power_xlvl$upper_ci)
    )

    # Compile results
    results <- list(
        population_model = population_model,
        sample_sizes = list(n_lvl1 = n_lvl1, n_lvl2 = n_lvl2),
        power_results = list(
            L1_direct = power_lvl1,
            L2_direct = power_lvl2,
            cross_level_interaction = power_xlvl
        ),
        power_summary = power_summary,
        power_summary_extended = power_summary_extended,
        parameters = list(
            lvl1_effect_std = lvl1_effect_std,
            lvl2_effect_std = lvl2_effect_std,
            xlvl_effect_std = xlvl_effect_std,
            icc = icc,
            rand_slope_std = rand_slope_std,
            alpha = alpha,
            n_sims = n_sims
        )
    )

    if (verbose) {
        cat(strrep("*", 60))
        cat("\nPOWER ANALYSIS SUMMARY\n")
        cat(strrep("*", 60))
        cat(sprintf("\nSample Sizes: n_lvl1 = %d, n_lvl2 = %d\n", n_lvl1, n_lvl2))
        cat("\nPower Results:\n")
        print(results$power_summary)
        cat("\nInterpretation: Power > 0.80 indicates adequate power\n")
    }

    class(results) <- "power_analysis_2level"

    # Return data frame directly if requested
    if (return_df) {
        return(power_summary_extended)
    }

    return(results)
}

#' Extract power summary data frame
#'
#' @param power_results Results object from power_analysis_two_level()
#' @param extended Logical, return extended summary with parameters (default: TRUE)
#' @return Data frame with power analysis results
#'
extract_power_data <- function(power_results, extended = TRUE) {
    if (!inherits(power_results, "power_analysis_2level")) {
        stop("Input must be a power_analysis_2level object")
    }

    if (extended && !is.null(power_results$power_summary_extended)) {
        return(power_results$power_summary_extended)
    } else {
        return(power_results$power_summary)
    }
}

#' Convert power results to long format for plotting
#'
#' @param power_results Results object from power_analysis_two_level()
#' @return Data frame in long format suitable for ggplot2
#'
power_to_long <- function(power_results) {
    if (!inherits(power_results, "power_analysis_2level")) {
        stop("Input must be a power_analysis_2level object")
    }

    df <- extract_power_data(power_results, extended = TRUE)

    # Convert to long format
    long_df <- df |>
        dplyr::select(Effect, Effect_Label, Power, Lower_CI, Upper_CI) |> # nolint
        tidyr::pivot_longer(
            cols = c(Power, Lower_CI, Upper_CI),
            names_to = "Metric",
            values_to = "Value"
        )

    return(long_df)
}

#' Enhanced print method
print.power_analysis_2level <- function(x, ...) {
    cat("Two-Level Power Analysis Results\n")
    cat("================================\n")
    cat(sprintf(
        "Sample Sizes: n_lvl1 = %d, n_lvl2 = %d\n",
        x$sample_sizes$n_lvl1, x$sample_sizes$n_lvl2
    ))
    cat("\nPower Results:\n")
    print(x$power_summary)
    return(cat("\nNote: Use extract_power_data() to get data frame for further analysis\n"))
}

#' Summary method that returns data frame
summary.power_analysis_2level <- function(object, extended = TRUE, ...) {
    return(extract_power_data(object, extended = extended))
}
