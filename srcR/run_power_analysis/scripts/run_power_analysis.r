#!/usr/bin/env Rscript

# import packages
library(dplyr) # masks stats::filter, lag; base::intersect, setdiff, setequal, union
library(furrr) # loads required package: future
library(here)
library(parallel)
library(tibble)
library(tictoc)
library(tidyr)

# set up options
options(tibble.width = Inf)

# review project and working directories using here
here::dr_here()

# get command line arguments; # todo: use the argparse package
args <- commandArgs(trailingOnly = TRUE)

# check if arguments are provided
if (length(args) < 1) {
    stop("One argument is required: version (i.e., 'dev' or 'prod')")
}

src_dir <- args[1]
proj_name <- args[2]
version <- args[3]
common_utils_path <- args[4]
config_path <- args[5]
utils_dir <- args[6]
data_dir <- args[7]

# # !--- NOT RUN: only uncomment when sourcing this script directly in R console
# version <- "dev"
# print(version)
# # !---

# run/source shared common utils script; # todo: use as argparse argument
source(glue::glue("{common_utils_path}"))

# load config file; # todo: use as argparse argument
config <- load_config(glue::glue("{config_path}"))
dplyr::glimpse(config)

# * run/source power analysis util script
source(glue::glue("{utils_dir}/power_analysis_utils.r"))

# set up parallel processing
# use config value if available, otherwise default to conservative setting
n_cores <- if (!is.null(config$params$max_cores)) {
    min(config$params$max_cores, parallel::detectCores() - 2)
} else {
    min(4, max(1, parallel::detectCores() - 4))
}
future::plan(multisession, workers = n_cores)

# create all parameter combinations using expand_grid
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

dplyr::glimpse(param_grid)

cat("Created parameter grid with", nrow(param_grid), "combinations\n")
cat("Running across", n_cores, "cores...\n")

# enhanced function wrapper with error handling
run_parallel_power_analysis <- function(params_row) {
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

# run parallel analysis with progress tracking
power_results <- split(param_grid, param_grid$run_id) |>
    future_map_dfr(
        run_parallel_power_analysis,
        .progress = TRUE,
        .options = furrr_options(
            seed = TRUE,
            # globals = c("power_analysis_two_level", "tic", "toc")
        )
    )

# clean up parallel backend
plan(sequential)

# check results
successful_results <- power_results |> dplyr::filter(success == TRUE)
dplyr::glimpse(successful_results)

failed_results <- power_results |> dplyr::filter(success == FALSE)
dplyr::glimpse(failed_results)

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

# display successful results
if (nrow(successful_results) > 0) {
    cat("\nSample of successful results:\n")
    successful_results |>
        select(-success) |>
        slice_head(n = 10) |>
        print()
}

# save results with timestamp
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
cat("\nSaving results with timestamp:", timestamp, "\n")

# save the results in two formats: rds and csv
readr::write_rds(power_results, glue::glue("{data_dir}/power_analysis_results_{timestamp}.rds"))
readr::write_csv(power_results, glue::glue("{data_dir}/power_analysis_results_{timestamp}.csv"))

cat(paste0("\nResults saved as power_analysis_results_", timestamp, ".rds/csv\n"))
