#!/usr/bin/env Rscript

# ---------------------------------------------------------------------------
# plot_utils.r - Shared plot utilities for analysis programs
#
# Provides: theme_apa, save_svg(), save_pdf()
#
# Requires: common_utils.r sourced first (for log_msg)
# ---------------------------------------------------------------------------

library(ggplot2)
library(svglite)


#' APA-like ggplot2 theme
#'
#' Minimal serif theme following APA style conventions. Apply globally via
#' theme_set(theme_apa) or per-plot via + theme_apa.
#'
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


#' Save a ggplot object as an SVG file
#'
#' @param plot    A ggplot object
#' @param filepath Full output path (including .svg extension)
#' @param width   Plot width in inches (default: 10)
#' @param height  Plot height in inches (default: 7)
#' @return NULL (invisible); called for side effect
#'
save_svg <- function(plot, filepath, width = 10, height = 7) {
    ggsave(filepath,
        plot = plot, device = "svg",
        width = width, height = height
    )
    log_msg("Saved: ", filepath)
    invisible(NULL)
}


#' Save a ggplot object as a PDF file
#'
#' @param plot    A ggplot object
#' @param filepath Full output path (including .pdf extension)
#' @param width   Plot width in inches (default: 10)
#' @param height  Plot height in inches (default: 7)
#' @return NULL (invisible); called for side effect
#'
save_pdf <- function(plot, filepath, width = 10, height = 7) {
    ggsave(filepath,
        plot = plot, device = "pdf",
        width = width, height = height
    )
    log_msg("Saved: ", filepath)
    invisible(NULL)
}
