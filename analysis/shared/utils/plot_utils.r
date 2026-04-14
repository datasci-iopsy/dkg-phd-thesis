#!/usr/bin/env Rscript

# ---------------------------------------------------------------------------
# plot_utils.r - Shared plot utilities for analysis programs
#
# Provides: theme_apa, save_svg(), save_pdf()
#
# Requires: common_utils.r sourced first (for log_msg)
# ---------------------------------------------------------------------------

library(ggplot2)
library(knitr)
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


#' Save a data frame as a GitHub-viewable Markdown table
#'
#' Writes a pipe-format Markdown table that GitHub renders natively.
#' Pass a named list of data frames to produce a multi-section document;
#' list names become section headers.
#'
#' @param x       A data frame/tibble, or a named list of data frames
#' @param filepath Full output path (including .md extension)
#' @return NULL (invisible); called for side effect
#'
save_md <- function(x, filepath) {
    if (is.data.frame(x)) {
        lines <- knitr::kable(x, format = "pipe")
    } else if (is.list(x)) {
        if (length(x) == 0) stop("save_md: x is an empty list; nothing to write to ", filepath)
        if (is.null(names(x))) stop("save_md: list x must have names; got an unnamed list")
        lines <- character(0)
        for (nm in names(x)) {
            lines <- c(lines, paste0("## ", nm), "", knitr::kable(x[[nm]], format = "pipe"), "")
        }
    } else {
        stop("save_md: x must be a data.frame or named list, got ", class(x)[[1]])
    }
    writeLines(lines, filepath)
    log_msg("Saved: ", filepath)
    invisible(NULL)
}
