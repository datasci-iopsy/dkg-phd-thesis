library(dplyr)
library(here)
library(furrr) # loads required package: future
library(parallel)
library(tibble)
library(tictoc)
library(tidyr)

# review directory
here::dr_here()

# load utils
source(here::here("R/utils/load_config.r"))
source(here::here("R/utils/power_analysis_two_level.r"))

# load config file
config <- load_config(here::here("R/configs/run_power_analysis.yaml"))
# print(config)
str(config)

# Set up parallel processing
n_cores <- min(parallel::detectCores() - 2) # cap by -2 cores to avoid overloading
future::plan(multisession, workers = n_cores)

# Create all parameter combinations using expand_grid
param_grid <- tidyr::expand_grid(
    n_lvl1 = config$params$n_lvl1,
    n_lvl2 = config$params$n_lvl2,
    lvl1_effect_std = config$params$lvl1_effect_std,
    lvl2_effect_std = config$params$lvl2_effect_std,
    xlvl_effect_std = config$params$xlvl_effect_std,
    icc = config$params$icc,
    rand_slope_std = config$params$rand_slope_std,
    alpha = config$params$alpha,
    use_REML = config$params$use_REML,
    n_sims = config$params$n_sims, # Consider increasing for final analysis
    verbose = config$params$verbose,
    return_df = config$params$return_df
) |>
    dplyr::mutate(
        run_id = row_number(),
        rand_seed = config$params$rand_seed + run_id # Unique seeds for each combination
    )

# print(param_grid)
str(param_grid)

cat("Created parameter grid with", nrow(param_grid), "combinations\n")
cat("Running across", n_cores, "cores...\n")

# Enhanced function wrapper with error handling
run_power_analysis_safe <- function(params_row) {
    tryCatch(
        {
            # Parameter validation
            if (any(is.na(params_row)) ||
                params_row$icc <= 0 || params_row$icc >= 1 ||
                any(c(
                    params_row$lvl1_effect_std, params_row$lvl2_effect_std,
                    params_row$xlvl_effect_std
                ) >= 1)) {
                return(tibble::tibble(
                    run_id = params_row$run_id,
                    error = "Invalid parameters",
                    success = FALSE
                ))
            }

            tictoc::tic()
            result <- power_analysis_two_level(
                n_lvl1 = params_row$n_lvl1,
                n_lvl2 = params_row$n_lvl2,
                lvl1_effect_std = params_row$lvl1_effect_std,
                lvl2_effect_std = params_row$lvl2_effect_std,
                xlvl_effect_std = params_row$xlvl_effect_std,
                icc = params_row$icc,
                rand_slope_std = params_row$rand_slope_std,
                alpha = params_row$alpha,
                use_REML = params_row$use_REML,
                n_sims = params_row$n_sims,
                verbose = params_row$verbose,
                return_df = params_row$return_df,
                rand_seed = params_row$rand_seed
            )
            elapsed_time <- tictoc::toc(quiet = TRUE)

            # Add metadata
            result |>
                dplyr::mutate(
                    run_id = params_row$run_id,
                    elapsed_time = elapsed_time$toc - elapsed_time$tic,
                    success = TRUE
                )
        },
        error = function(e) {
            return(
                tibble::tibble(
                    run_id = params_row$run_id,
                    error = as.character(e),
                    success = FALSE
                )
            )
        }
    )
}

# Run parallel analysis with progress tracking
power_results <- split(param_grid$run_id) |>
    future_map_dfr(
        run_power_analysis_safe,
        .progress = TRUE,
        .options = furrr_options(
            seed = TRUE,
            # globals = c("power_analysis_two_level", "tic", "toc")
        )
    )

# Clean up parallel backend
plan(sequential)

tibble::tibble(power_results)

# Check results
successful_results <- power_results |> filter(success == TRUE)
failed_results <- power_results |> filter(success == FALSE)

cat("\nResults Summary:\n")
cat("Total parameter combinations:", nrow(param_grid), "\n")
cat("Successful runs:", nrow(successful_results), "\n")
cat("Failed runs:", nrow(failed_results), "\n")

if (nrow(failed_results) > 0) {
    cat("\nError summary:\n")
    failed_results |>
        count(error, sort = TRUE) |>
        print()
}

# # Display successful results
# if (nrow(successful_results) > 0) {
#     cat("\nSample of successful results:\n")
#     successful_results |>
#         select(-success) |>
#         slice_head(n = 10) |>
#         print()

#     # Save results with timestamp
#     timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
#     write_rds(power_results, paste0("power_analysis_results_", timestamp, ".rds"))
#     write_csv(
#         successful_results |> select(-success),
#         paste0("power_analysis_results_", timestamp, ".csv")
#     )

#     cat(paste0("\nResults saved as power_analysis_results_", timestamp, ".rds/csv\n"))
# }

# # Display final results
# power_results |>
#     filter(success == TRUE) |>
#     select(-success, -run_id, -elapsed_time)

# Plot power curves
library(ggplot2)
ggplot2::ggplot(power_results, aes(x = N_Level2, y = Power, color = Effect)) +
    geom_line(linewidth = 1) +
    geom_point(size = 2) +
    geom_hline(yintercept = 0.8, linetype = "dashed", alpha = 0.5) +
    labs(
        title = "Power Analysis: Sample Size Effects",
        x = "Level 2 Sample Size (n_lvl2)",
        y = "Statistical Power",
        color = "Effect Type"
    ) +
    theme_minimal() +
    ylim(0, 1)

# # Create comparison plot across different sample sizes
# sample_sizes <- c(100, 300, 500)
# power_comparison <- tibble::tibble()

# for (n in sample_sizes) {
#     temp_df <- power_analysis_two_level(
#         n_lvl1 = 3,
#         n_lvl2 = n,
#         lvl1_effect_std = 0.1,
#         lvl2_effect_std = 0.3,
#         xlvl_effect_std = 0.5,
#         icc = 0.42, # avg for repeated measures; pg. 4
#         rand_slope_std = 0.09, # medium tau_11_std; pg. 7
#         alpha = 0.05,
#         use_REML = TRUE,
#         n_sims = 10,
#         verbose = TRUE,
#         return_df = TRUE,
#         rand_seed = 8762
#     )
#     power_comparison <- rbind(power_comparison, temp_df)
# }

# tibble::tibble(power_comparison)

# # Plot power curves
# ggplot(power_comparison, aes(x = N_Level2, y = Power, color = Effect)) +
#     geom_line(linewidth = 1) +
#     geom_point(size = 2) +
#     geom_hline(yintercept = 0.8, linetype = "dashed", alpha = 0.5) +
#     labs(
#         title = "Power Analysis: Sample Size Effects",
#         x = "Level 2 Sample Size (n_lvl2)",
#         y = "Statistical Power",
#         color = "Effect Type"
#     ) +
#     theme_minimal() +
#     ylim(0, 1)
