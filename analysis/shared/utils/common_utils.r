#!/usr/bin/env Rscript

# ---------------------------------------------------------------------------
# common_utils.r - Shared utilities for analysis programs
#
# Provides: log_msg(), load_config(), get_system_info(), ensure_dir()
# ---------------------------------------------------------------------------

library(glue)
library(yaml)


#' Log a timestamped message to stdout
#'
#' @param ... Message components (passed to paste0)
#' @return NULL (invisible); called for side effect
#'
log_msg <- function(...) {
    timestamp <- format(Sys.time(), "[%Y-%m-%d %H:%M:%S]")
    cat(timestamp, paste0(...), "\n")
}


#' Load and validate a YAML configuration file
#'
#' @param config_path Path to YAML configuration file
#' @param required_sections Character vector of top-level sections that must
#'   be present (default: "params")
#' @return Parsed configuration list
#'
load_config <- function(config_path, required_sections = c("params")) {
    if (!file.exists(config_path)) {
        stop(glue::glue("Configuration file not found: {config_path}"))
    }

    config <- yaml::read_yaml(config_path)

    missing <- setdiff(required_sections, names(config))
    if (length(missing) > 0) {
        stop(
            "Missing required configuration sections: ",
            paste(missing, collapse = ", ")
        )
    }

    return(config)
}


#' Print system information (cross-platform)
#'
#' Reports OS, CPU cores, and memory. Works on macOS and Linux.
#'
#' @return NULL (invisible); called for side effect (logs to stdout)
#'
get_system_info <- function() {
    info <- Sys.info()
    log_msg("System: ", info["sysname"], " ", info["release"])
    log_msg("Machine: ", info["nodename"])

    n_cores <- parallel::detectCores(logical = TRUE)
    log_msg("Available cores (logical): ", n_cores)

    os <- tolower(info["sysname"])

    if (os == "darwin") {
        mem_bytes <- as.numeric(system("sysctl -n hw.memsize", intern = TRUE))
        log_msg("Physical memory: ", round(mem_bytes / 1024^3, 1), " GB")
    } else if (os == "linux") {
        mem_line <- system("free -h | awk '/^Mem:/ {print $2}'", intern = TRUE)
        avail_line <- system("free -h | awk '/^Mem:/ {print $7}'", intern = TRUE)
        log_msg("Physical memory: ", mem_line)
        log_msg("Available memory: ", avail_line)
    } else {
        log_msg("Memory info not available for this OS")
    }
}


#' Stop loudly if any target is missing or older than its newest prerequisite
#'
#' Mirrors make(1) newer-than semantics. Call at the top of each pipeline
#' stage before reading inputs. Passes silently when all targets are fresh.
#'
#' @param targets       character; paths that must exist and be up to date
#' @param prerequisites character; paths the targets depend on
#' @param remediation   character; exact command to print on failure
#' @return NULL (invisible); called for side effect
#'
require_fresh <- function(targets, prerequisites, remediation) {
    for (t in targets) {
        if (!file.exists(t)) {
            stop(
                "Missing required file: ", t,
                "\nRun: ", remediation
            )
        }
    }

    t_mtime <- min(file.info(targets)$mtime)
    p_mtime <- max(file.info(prerequisites)$mtime)

    if (t_mtime < p_mtime) {
        stale <- targets[file.info(targets)$mtime < p_mtime]
        stop(
            "Stale outputs detected (older than their inputs):\n",
            paste0("  ", stale, collapse = "\n"),
            "\nRun: ", remediation
        )
    }

    invisible(NULL)
}


#' Ensure a directory exists, creating it if necessary
#'
#' @param path Directory path to create
#' @param verbose Log a message when creating (default: TRUE)
#' @return The normalized path (invisible)
#'
ensure_dir <- function(path, verbose = TRUE) {
    if (!dir.exists(path)) {
        dir.create(path, recursive = TRUE)
        if (verbose) {
            log_msg("Created directory: ", path)
        }
    }
    invisible(normalizePath(path))
}
