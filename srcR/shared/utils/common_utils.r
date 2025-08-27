#!/usr/bin/env Rscript

# import packages
library(glue)
library(yaml)

#' Load and validate power analysis configuration
#' @param config_path Path to YAML configuration file
#' @return Configuration object
#'

load_config <- function(config_path) {
    # check if config file exists
    if (!file.exists(config_path)) {
        stop(glue::glue("Configuration file not found: {config_path}"))
    }
    # load configuration
    config <- yaml::read_yaml(config_path)

    # validate required sections
    required_sections <- c("params")
    missing_sections <- setdiff(required_sections, names(config))
    if (length(missing_sections) > 0) {
        stop(
            "Missing required configuration sections: ",
            paste(missing_sections, collapse = ", ")
        )
    }
    return(config)
}
