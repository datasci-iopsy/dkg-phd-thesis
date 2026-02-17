#!/usr/bin/env Rscript

# ---------------------------------------------------------------------------
# run_power_analysis.r - Orchestration script for power analysis grid
#
# Builds a full factorial parameter grid from config, distributes across
# parallel workers via furrr, and saves timestamped results.
#
# Usage: Rscript run_power_analysis.r --version <dev|prod>
#        (Normally invoked by main.sh, not called directly)
# ---------------------------------------------------------------------------

# [1] Options and argument parsing ----------------------------------------

options(
    repos = c(CRAN = "https://cloud.r-project.org/"),
    tibble.width = Inf
)

library(argparse)

parser <- ArgumentParser(description = "Run power analysis simulation grid")
parser$add_argument(
    "--version",
    type = "character",
    required = TRUE,
    choices = c("dev", "prod"),
    help = "Configuration version to use (dev or prod)"
)
args <- parser$parse_args()
version <- args$version


# [2] Path resolution -----------------------------------------------------

# Derive all paths from this script's filesystem location.
# Expected location: analysis/run_power_analysis/scripts/run_power_analysis.r

resolve_paths <- function(version) {
    # Get the directory containing this script
    script_args <- commandArgs(trailingOnly = FALSE)
    file_arg <- grep("^--file=", script_args, value = TRUE)

    if (length(file_arg) > 0) {
        # Called via Rscript
        script_path <- normalizePath(sub("^--file=", "", file_arg))
    } else {
        # Sourced interactively -- fall back to working directory
        script_path <- normalizePath(file.path(getwd(), "scripts", "run_power_analysis.r"))
    }

    scripts_dir <- dirname(script_path)
    program_dir <- dirname(scripts_dir)
    analysis_dir <- dirname(program_dir)

    paths <- list(
        script = script_path,
        program_dir = program_dir,
        analysis_dir = analysis_dir,
        common_utils = file.path(analysis_dir, "shared", "utils", "common_utils.r"),
        config = file.path(
            program_dir, "configs",
            paste0("run_power_analysis.", version, ".yaml")
        ),
        utils_dir = file.path(program_dir, "utils"),
        data_dir = file.path(program_dir, "data"),
        log_dir = file.path(program_dir, "logs"),
        figs_dir = file.path(program_dir, "figs")
    )

    # Validate that required source files exist
    required_files <- c("common_utils", "config")
    for (name in required_files) {
        if (!file.exists(paths[[name]])) {
            stop(paste0(
                "Required file not found: ", paths[[name]],
                " (resolved from script at ", script_path, ")"
            ))
        }
    }

    utils_file <- file.path(paths$utils_dir, "power_analysis_utils.r")
    if (!file.exists(utils_file)) {
        stop(paste0("Required file not found: ", utils_file))
    }

    return(paths)
}

paths <- resolve_paths(version)


# [3] Source dependencies -------------------------------------------------

source(paths$common_utils)
source(file.path(paths$utils_dir, "power_analysis_utils.r"))

# Ensure runtime directories exist
ensure_dir(paths$data_dir)
ensure_dir(paths$log_dir)
ensure_dir(paths$figs_dir)


# [4] Startup logging ----------------------------------------------------

log_msg("run_power_analysis -- version: ", version)
log_msg("Script: ", paths$script)
log_msg("Program directory: ", paths$program_dir)
log_msg("Config: ", paths$config)
log_msg("Data output: ", paths$data_dir)
log_msg("")
get_system_info()
log_msg("")


# [5] Load config and build parameter grid --------------------------------

# Import remaining packages (common_utils.r and power_analysis_utils.r
# already loaded their own dependencies)
library(dplyr)
library(furrr)
library(parallel)
library(parallelly)
library(RhpcBLASctl)
library(tibble)
library(tictoc)
library(tidyr)

config <- load_config(paths$config)
log_msg("Configuration loaded:")
dplyr::glimpse(config)

# Full factorial grid of all parameter combinations
param_grid <- tidyr::expand_grid(
    n_lvl1           = config$params$n_lvl1,
    n_lvl2           = config$params$n_lvl2,
    lvl1_effect_std  = config$params$lvl1_effect_std,
    lvl2_effect_std  = config$params$lvl2_effect_std,
    xlvl_effect_std  = config$params$xlvl_effect_std,
    icc              = config$params$icc,
    rand_slope_std   = config$params$rand_slope_std,
    alpha            = config$params$alpha,
    use_REML         = config$params$use_REML,
    n_sims           = config$params$n_sims,
    verbose          = config$params$verbose,
    return_df        = config$params$return_df
) |>
    dplyr::mutate(
        run_id    = dplyr::row_number(),
        rand_seed = config$params$rand_seed + run_id
    )

dplyr::glimpse(param_grid)
log_msg("Parameter grid: ", nrow(param_grid), " combinations")


# [6] Parallel setup ------------------------------------------------------

# Pin BLAS threads to 1 to prevent oversubscription in parallel workers.
# Each furrr worker should use exactly one core for linear algebra.
RhpcBLASctl::blas_set_num_threads(1)

# Determine core count: use config value (capped by hardware) or default
n_cores <- if (!is.null(config$params$max_cores)) {
    min(config$params$max_cores, parallelly::availableCores() - 2L)
} else {
    min(4L, max(1L, parallelly::availableCores() - 4L))
}

if (.Platform$OS.type == "unix") {
    future::plan(multicore, workers = n_cores)
} else {
    future::plan(multisession, workers = n_cores)
}

log_msg("Parallel backend: ", n_cores, " cores")


# [7] Execute grid --------------------------------------------------------

# Wrapper with error handling and per-run timing
run_parallel_power_analysis <- function(params_row) {
    tryCatch(
        {
            # Parameter validation
            if (any(is.na(params_row)) ||
                params_row$icc <= 0 || params_row$icc >= 1 ||
                any(c(
                    params_row$lvl1_effect_std,
                    params_row$lvl2_effect_std,
                    params_row$xlvl_effect_std
                ) >= 1)) {
                return(tibble::tibble(
                    run_id  = params_row$run_id,
                    error   = "Invalid parameters",
                    success = FALSE
                ))
            }

            tictoc::tic()
            result <- power_analysis_two_level(
                n_lvl1          = params_row$n_lvl1,
                n_lvl2          = params_row$n_lvl2,
                lvl1_effect_std = params_row$lvl1_effect_std,
                lvl2_effect_std = params_row$lvl2_effect_std,
                xlvl_effect_std = params_row$xlvl_effect_std,
                icc             = params_row$icc,
                rand_slope_std  = params_row$rand_slope_std,
                alpha           = params_row$alpha,
                use_REML        = params_row$use_REML,
                n_sims          = params_row$n_sims,
                verbose         = params_row$verbose,
                return_df       = params_row$return_df,
                rand_seed       = params_row$rand_seed
            )
            elapsed_time <- tictoc::toc(quiet = TRUE)

            result |>
                dplyr::mutate(
                    run_id       = params_row$run_id,
                    elapsed_time = elapsed_time$toc - elapsed_time$tic,
                    success      = TRUE
                )
        },
        error = function(e) {
            tibble::tibble(
                run_id  = params_row$run_id,
                error   = as.character(e),
                success = FALSE
            )
        }
    )
}

log_msg("Starting simulation grid...")

power_results <- split(param_grid, param_grid$run_id) |>
    furrr::future_map_dfr(
        run_parallel_power_analysis,
        .progress = TRUE,
        .options = furrr::furrr_options(seed = TRUE)
    )

# Restore sequential execution
future::plan(future::sequential)

log_msg("Simulation grid complete")


# [8] Report and save -----------------------------------------------------

successful_results <- power_results |> dplyr::filter(success == TRUE)
failed_results <- power_results |> dplyr::filter(success == FALSE)

log_msg("Results summary:")
log_msg("  Total parameter combinations: ", nrow(param_grid))
log_msg("  Successful runs: ", nrow(successful_results))
log_msg("  Failed runs: ", nrow(failed_results))

if (nrow(failed_results) > 0) {
    log_msg("Error breakdown:")
    failed_results |>
        dplyr::count(error, sort = TRUE) |>
        print()
}

if (nrow(successful_results) > 0) {
    log_msg("Sample of successful results:")
    successful_results |>
        dplyr::select(-success) |>
        dplyr::slice_head(n = 10) |>
        print()
}

# Save results with timestamp
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
rds_path <- file.path(paths$data_dir, paste0("power_analysis_results_", timestamp, ".rds"))
csv_path <- file.path(paths$data_dir, paste0("power_analysis_results_", timestamp, ".csv"))

readr::write_rds(power_results, rds_path)
readr::write_csv(power_results, csv_path)

log_msg("Results saved as power_analysis_results_", timestamp, ".rds/.csv")
log_msg("Output directory: ", paths$data_dir)
