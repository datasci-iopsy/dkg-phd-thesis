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

# # ! NOT RUN - still in development
# # shared/utils/common_utils.R
# library(glue)
# library(here)
# library(yaml)

# #' Load configuration with validation and defaults
# #' @param config_path Path to YAML configuration file
# #' @param project_name Name of the project for logging
# #' @return Validated configuration object
# load_config <- function(config_path, project_name = "unknown") {
#     if (!file.exists(config_path)) {
#         stop(glue::glue("Configuration file not found: {config_path}"))
#     }

#     config <- yaml::read_yaml(config_path)

#     # Add logging
#     cat(glue::glue("[{Sys.time()}] Loading config for {project_name}: {config_path}\n"))

#     # Validate and merge with defaults
#     config <- validate_and_merge_config(config, project_name)

#     return(config)
# }

# #' Validate configuration structure
# validate_and_merge_config <- function(config, project_name) {
#     # Load project-specific default configurations
#     default_config_path <- here::here("shared", "configs", "default_settings.yaml")

#     if (file.exists(default_config_path)) {
#         defaults <- yaml::read_yaml(default_config_path)
#         config <- modifyList(defaults, config)
#     }

#     # Project-specific validation
#     required_sections <- get_required_sections(project_name)
#     missing_sections <- setdiff(required_sections, names(config))

#     if (length(missing_sections) > 0) {
#         stop(glue::glue("Missing required configuration sections for {project_name}: {paste(missing_sections, collapse = ', ')}"))
#     }

#     return(config)
# }
